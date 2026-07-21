package castv2

import (
	"encoding/binary"
	"fmt"
	"io"
)

// The CASTV2 wire protocol is a 4-byte big-endian length prefix
// followed by one protobuf-encoded CastMessage. The message is a
// handful of scalar fields that have not changed since the protocol
// shipped, so the codec is hand-rolled here instead of pulling a
// protobuf dependency into the server for one fixed shape.

// maxFrameBytes bounds a frame. The protocol caps messages at 64 KiB;
// anything larger is a broken or hostile peer.
const maxFrameBytes = 64 << 10

// CastMessage field numbers from the cast channel proto.
const (
	fieldProtocolVersion = 1
	fieldSourceID        = 2
	fieldDestinationID   = 3
	fieldNamespace       = 4
	fieldPayloadType     = 5
	fieldPayloadUTF8     = 6

	payloadTypeString = 0
)

// Message is one CastMessage. Only string payloads are modeled: the
// namespaces WaxDeck speaks never carry binary payloads.
type Message struct {
	SourceID      string
	DestinationID string
	Namespace     string
	PayloadUTF8   string
}

// marshal encodes the protobuf body without the length prefix. Every
// field is written even when empty; the upstream proto declares them
// required.
func (m Message) marshal() []byte {
	b := make([]byte, 0, 64+len(m.Namespace)+len(m.PayloadUTF8))
	b = append(b, fieldProtocolVersion<<3, 0)
	b = appendStringField(b, fieldSourceID, m.SourceID)
	b = appendStringField(b, fieldDestinationID, m.DestinationID)
	b = appendStringField(b, fieldNamespace, m.Namespace)
	b = append(b, fieldPayloadType<<3, payloadTypeString)
	b = appendStringField(b, fieldPayloadUTF8, m.PayloadUTF8)
	return b
}

// appendStringField appends one length-delimited field. Field numbers
// here all fit a single tag byte.
func appendStringField(b []byte, field int, s string) []byte {
	b = append(b, byte(field<<3|2))
	b = binary.AppendUvarint(b, uint64(len(s)))
	return append(b, s...)
}

// WriteMessage frames and writes one message in a single Write call so
// concurrent writers interleave at frame granularity, never inside one.
func WriteMessage(w io.Writer, m Message) error {
	body := m.marshal()
	if len(body) > maxFrameBytes {
		return fmt.Errorf("castv2: message of %d bytes exceeds %d byte frame limit", len(body), maxFrameBytes)
	}
	frame := make([]byte, 4, 4+len(body))
	binary.BigEndian.PutUint32(frame, uint32(len(body)))
	frame = append(frame, body...)
	if _, err := w.Write(frame); err != nil {
		return fmt.Errorf("castv2: writing frame: %w", err)
	}
	return nil
}

// ReadMessage reads one framed message.
func ReadMessage(r io.Reader) (Message, error) {
	var hdr [4]byte
	if _, err := io.ReadFull(r, hdr[:]); err != nil {
		return Message{}, fmt.Errorf("castv2: reading frame header: %w", err)
	}
	n := binary.BigEndian.Uint32(hdr[:])
	if n > maxFrameBytes {
		return Message{}, fmt.Errorf("castv2: frame of %d bytes exceeds %d byte limit", n, maxFrameBytes)
	}
	body := make([]byte, n)
	if _, err := io.ReadFull(r, body); err != nil {
		return Message{}, fmt.Errorf("castv2: reading frame body: %w", err)
	}
	return unmarshalMessage(body)
}

// unmarshalMessage decodes the protobuf body. Unknown fields are
// skipped by wire type so newer peers stay decodable; only the
// deprecated group wire types are rejected, since they cannot be
// skipped without understanding them.
func unmarshalMessage(b []byte) (Message, error) {
	var m Message
	for len(b) > 0 {
		tag, n := binary.Uvarint(b)
		if n <= 0 {
			return Message{}, fmt.Errorf("castv2: truncated field tag")
		}
		b = b[n:]
		field, wire := tag>>3, tag&7
		switch wire {
		case 0: // varint
			v, n := binary.Uvarint(b)
			if n <= 0 {
				return Message{}, fmt.Errorf("castv2: truncated varint in field %d", field)
			}
			b = b[n:]
			if field == fieldPayloadType && v != payloadTypeString {
				return Message{}, fmt.Errorf("castv2: unsupported payload type %d", v)
			}
		case 2: // length-delimited
			l, n := binary.Uvarint(b)
			if n <= 0 || l > uint64(len(b)-n) {
				return Message{}, fmt.Errorf("castv2: truncated bytes in field %d", field)
			}
			s := string(b[n : n+int(l)])
			b = b[n+int(l):]
			switch field {
			case fieldSourceID:
				m.SourceID = s
			case fieldDestinationID:
				m.DestinationID = s
			case fieldNamespace:
				m.Namespace = s
			case fieldPayloadUTF8:
				m.PayloadUTF8 = s
			}
		case 1: // fixed64
			if len(b) < 8 {
				return Message{}, fmt.Errorf("castv2: truncated fixed64 in field %d", field)
			}
			b = b[8:]
		case 5: // fixed32
			if len(b) < 4 {
				return Message{}, fmt.Errorf("castv2: truncated fixed32 in field %d", field)
			}
			b = b[4:]
		default:
			return Message{}, fmt.Errorf("castv2: unsupported wire type %d in field %d", wire, field)
		}
	}
	return m, nil
}
