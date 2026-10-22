package service

// projectURL is where the operator of a host this server talks to can
// read about what is asking.
const projectURL = "https://github.com/colespringer/waxdeck"

// UserAgentFor names one build. An unstamped build says dev rather than
// leaving the version out, so the agent keeps one shape.
func UserAgentFor(version string) string {
	if version == "" {
		version = "dev"
	}
	return "WaxDeck/" + version + " (+" + projectURL + ")"
}

// UserAgent is the agent on the requests this server makes on its own
// behalf. Hosts refuse a client that does not say who it is (Buzzsprout
// answers a bare Go client 403).
func (l *Library) UserAgent() string { return UserAgentFor(l.version) }
