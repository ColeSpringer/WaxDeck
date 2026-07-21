package castv2

import (
	"bytes"
	"encoding/binary"
	"strings"
	"testing"
)

func TestMessageRoundTrip(t *testing.T) {
	cases := []struct {
		name string
		msg  Message
	}{
		{"heartbeat", Message{SourceID: "sender-0", DestinationID: "receiver-0", Namespace: NamespaceHeartbeat, PayloadUTF8: `{"type":"PING"}`}},
		{"empty payload", Message{SourceID: "sender-0", DestinationID: "receiver-0", Namespace: NamespaceConnection}},
		{"transport ids", Message{SourceID: "sender-0", DestinationID: "transport-42", Namespace: NamespaceMedia, PayloadUTF8: `{"type":"GET_STATUS","requestId":7}`}},
		{"long payload", Message{SourceID: "s", DestinationID: "d", Namespace: NamespaceMedia, PayloadUTF8: strings.Repeat("x", 4096)}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var buf bytes.Buffer
			if err := WriteMessage(&buf, tc.msg); err != nil {
				t.Fatalf("WriteMessage: %v", err)
			}
			got, err := ReadMessage(&buf)
			if err != nil {
				t.Fatalf("ReadMessage: %v", err)
			}
			if got != tc.msg {
				t.Errorf("round trip mismatch:\n got %+v\nwant %+v", got, tc.msg)
			}
		})
	}
}

// cannedFrame builds the wire bytes for the heartbeat PING by hand,
// mirroring what a real sender emits.
func cannedFrame(t *testing.T) ([]byte, Message) {
	t.Helper()
	msg := Message{
		SourceID:      "sender-0",
		DestinationID: "receiver-0",
		Namespace:     NamespaceHeartbeat,
		PayloadUTF8:   `{"type":"PING"}`,
	}
	body := []byte{0x08, 0x00} // protocol_version = 0
	body = append(body, 0x12, byte(len(msg.SourceID)))
	body = append(body, msg.SourceID...)
	body = append(body, 0x1a, byte(len(msg.DestinationID)))
	body = append(body, msg.DestinationID...)
	body = append(body, 0x22, byte(len(msg.Namespace)))
	body = append(body, msg.Namespace...)
	body = append(body, 0x28, 0x00) // payload_type = string
	body = append(body, 0x32, byte(len(msg.PayloadUTF8)))
	body = append(body, msg.PayloadUTF8...)
	frame := binary.BigEndian.AppendUint32(nil, uint32(len(body)))
	return append(frame, body...), msg
}

func TestMessageCannedVector(t *testing.T) {
	frame, msg := cannedFrame(t)

	var buf bytes.Buffer
	if err := WriteMessage(&buf, msg); err != nil {
		t.Fatalf("WriteMessage: %v", err)
	}
	if !bytes.Equal(buf.Bytes(), frame) {
		t.Errorf("encoded frame mismatch:\n got % x\nwant % x", buf.Bytes(), frame)
	}

	got, err := ReadMessage(bytes.NewReader(frame))
	if err != nil {
		t.Fatalf("ReadMessage: %v", err)
	}
	if got != msg {
		t.Errorf("decoded message mismatch:\n got %+v\nwant %+v", got, msg)
	}
}

func TestDecodeSkipsUnknownFields(t *testing.T) {
	frame, msg := cannedFrame(t)
	body := frame[4:]
	// Unknown fields in every skippable wire type: 7 length-delimited,
	// 8 varint, 9 fixed32, 10 fixed64.
	body = append(body, 0x3a, 0x03, 0xde, 0xad, 0xbe)
	body = append(body, 0x40, 0x2a)
	body = append(body, 0x4d, 1, 2, 3, 4)
	body = append(body, 0x51, 1, 2, 3, 4, 5, 6, 7, 8)

	got, err := unmarshalMessage(body)
	if err != nil {
		t.Fatalf("unmarshalMessage: %v", err)
	}
	if got != msg {
		t.Errorf("decoded message mismatch:\n got %+v\nwant %+v", got, msg)
	}
}

func TestDecodeRejectsOversizeFrame(t *testing.T) {
	hdr := binary.BigEndian.AppendUint32(nil, maxFrameBytes+1)
	if _, err := ReadMessage(bytes.NewReader(hdr)); err == nil {
		t.Fatal("expected an error for an oversize frame")
	}
}

func TestDecodeRejectsTruncatedField(t *testing.T) {
	// Field 2 claims 10 bytes but only 3 follow.
	body := []byte{0x12, 0x0a, 'a', 'b', 'c'}
	if _, err := unmarshalMessage(body); err == nil {
		t.Fatal("expected an error for a truncated field")
	}
}
