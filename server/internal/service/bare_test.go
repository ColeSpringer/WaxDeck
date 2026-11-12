package service

// bareLibrary is a Library over c with every domain built and no catalog,
// for tests of code that needs no Open.
func bareLibrary(c *core) *Library {
	l := &Library{core: c}
	c.library = l
	c.wire(Config{})
	return l
}
