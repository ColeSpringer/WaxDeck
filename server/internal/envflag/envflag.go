// Package envflag defines typed command-line flags whose defaults come from
// WAXDECK_* variables, and refuses a value the flag could not have taken
// rather than start on a default nobody chose.
package envflag

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"strconv"
)

// Set defines flags on one FlagSet and keeps the variables it could not read.
type Set struct {
	fs     *flag.FlagSet
	faults []fault
}

type fault struct {
	flag string
	err  error
}

// New defines flags on fs.
func New(fs *flag.FlagSet) *Set { return &Set{fs: fs} }

// Bool reads key with the spellings the flag's own parser takes.
func (s *Set) Bool(name, key string, def bool, usage string) *bool {
	if v := os.Getenv(key); v != "" {
		if b, err := strconv.ParseBool(v); err == nil {
			def = b
		} else {
			s.refuse(name, "%s is %q; want true or false", key, v)
		}
	}
	return s.fs.Bool(name, def, usage)
}

// Int reads key as a whole number.
func (s *Set) Int(name, key string, def int, usage string) *int {
	return s.fs.Int(name, int(s.number(name, key, int64(def), strconv.IntSize)), usage)
}

// Int64 reads key as a whole number.
func (s *Set) Int64(name, key string, def int64, usage string) *int64 {
	return s.fs.Int64(name, s.number(name, key, def, 64), usage)
}

func (s *Set) number(name, key string, def int64, bits int) int64 {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	n, err := strconv.ParseInt(v, 10, bits)
	if err != nil {
		s.refuse(name, "%s is %q; want a whole number", key, v)
		return def
	}
	return n
}

func (s *Set) refuse(name, format string, args ...any) {
	s.faults = append(s.faults, fault{flag: name, err: fmt.Errorf(format, args...)})
}

// Err names every unreadable variable whose flag the command line left
// unset; a flag beats the environment. Call it after parsing.
func (s *Set) Err() error {
	set := map[string]bool{}
	s.fs.Visit(func(f *flag.Flag) { set[f.Name] = true })
	var errs []error
	for _, f := range s.faults {
		if !set[f.flag] {
			errs = append(errs, f.err)
		}
	}
	return errors.Join(errs...)
}
