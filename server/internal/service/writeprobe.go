package service

import "os"

// probeWritable reports whether the server can create a file in dir, by
// creating one and removing it again.
func probeWritable(dir string) error {
	f, err := os.CreateTemp(dir, ".waxdeck-write-probe-*")
	if err != nil {
		return err
	}
	name := f.Name()
	if err := f.Close(); err != nil {
		os.Remove(name)
		return err
	}
	return os.Remove(name)
}
