package pagetext

import (
	"strconv"
	"time"
)

// esShortMonths is CLDR's Spanish abbreviations, copied from intl
// 0.20.2 as the app ships it rather than written from memory: the app
// formats the same dates through that package, so verbatim is what
// keeps the two agreeing. September is "sept", and none take a period.
var esShortMonths = [12]string{
	"ene", "feb", "mar", "abr", "may", "jun",
	"jul", "ago", "sept", "oct", "nov", "dic",
}

// es is machine-drafted and awaiting a native reader; the shape is
// pinned by tests, the wording is not.
var es = Strings{
	Lang: "es",
	// CLDR's es yMMMd is "d MMM y", which is where "12 ago 2026" comes
	// from. Assembled by hand because pulling a CLDR formatter in for
	// one date on three pages is not worth the dependency.
	FormatDate: func(t time.Time) string {
		return strconv.Itoa(t.Day()) + " " + esShortMonths[t.Month()-1] + " " + strconv.Itoa(t.Year())
	},

	ShareDownload:      "Descargar",
	ShareSharedWith:    "Compartido con WaxDeck",
	ShareExpiresPrefix: "el enlace caduca el",
	ShareNotFoundTitle: "No encontrado",
	ShareNotFoundBody:  "Este enlace no existe, ha caducado o fue revocado.",

	OidcTitle:              "Inicio de sesión de WaxDeck",
	OidcCodeHeading:        "Ya casi está",
	OidcCodeBody:           "Introduce este código de un solo uso en la aplicación para terminar de iniciar sesión. Caduca en unos minutos.",
	OidcErrorHeading:       "No se pudo iniciar sesión",
	OidcBackLink:           "Volver a WaxDeck",
	OidcNotConfigured:      "el inicio de sesión único no está configurado en este servidor",
	OidcProviderReported:   "el proveedor de identidad informó: %s %s",
	OidcIncompleteCallback: "el proveedor de identidad envió una respuesta incompleta",
	OidcCouldNotComplete:   "no se pudo completar el inicio de sesión",
	OidcUnknownMode:        "modo de flujo desconocido",

	LastfmFailedTitle:    "Error de conexión con Last.fm",
	LastfmFailedBody:     "no se pudo completar la autorización",
	LastfmConnectedTitle: "Last.fm conectado",
	LastfmConnectedBody:  "Conectado como %s. Puedes cerrar esta ventana; WaxDeck enviará tus scrobbles a partir de ahora.",
}
