module github.com/colespringer/waxdeck/server

go 1.26.3

tool github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen

require (
	github.com/colespringer/waxdeck/fixtures v0.0.0-00010101000000-000000000000
	github.com/coreos/go-oidc/v3 v3.20.0
	github.com/getkin/kin-openapi v0.135.0
	github.com/oapi-codegen/runtime v1.4.2
	golang.org/x/crypto v0.54.0
	golang.org/x/oauth2 v0.36.0
)

require github.com/go-jose/go-jose/v4 v4.1.4 // indirect

require (
	github.com/apapsch/go-jsonmerge/v2 v2.0.0 // indirect
	github.com/colespringer/waxbin v0.0.0-20260718124056-6bed909ad5a8
	github.com/colespringer/waxflow v0.0.0-20260718120944-c4a5e80a3fef
	github.com/colespringer/waxflow/cli v0.0.0-20260718120944-c4a5e80a3fef
	github.com/colespringer/waxlabel v1.2.0 // indirect
	github.com/dprotaso/go-yit v0.0.0-20220510233725-9ba8df137936 // indirect
	github.com/dustin/go-humanize v1.0.1 // indirect
	github.com/fsnotify/fsnotify v1.9.0 // indirect
	github.com/go-openapi/jsonpointer v0.22.4 // indirect
	github.com/go-openapi/swag/jsonname v0.25.4 // indirect
	github.com/gofrs/flock v0.13.0 // indirect
	github.com/google/uuid v1.6.0 // indirect
	github.com/inconshreveable/mousetrap v1.1.0 // indirect
	github.com/josharian/intern v1.0.0 // indirect
	github.com/mailru/easyjson v0.9.1 // indirect
	github.com/mattn/go-isatty v0.0.20 // indirect
	github.com/mohae/deepcopy v0.0.0-20170929034955-c48cc78d4826 // indirect
	github.com/ncruces/go-strftime v1.0.0 // indirect
	github.com/oapi-codegen/oapi-codegen/v2 v2.7.2 // indirect
	github.com/oasdiff/yaml v0.0.9 // indirect
	github.com/oasdiff/yaml3 v0.0.9 // indirect
	github.com/oklog/ulid/v2 v2.1.1
	github.com/perimeterx/marshmallow v1.1.5 // indirect
	github.com/remyoudompheng/bigfft v0.0.0-20230129092748-24d4a6f8daec // indirect
	github.com/speakeasy-api/jsonpath v0.6.3 // indirect
	github.com/speakeasy-api/openapi v1.19.2 // indirect
	github.com/spf13/cobra v1.10.2 // indirect
	github.com/spf13/pflag v1.0.9 // indirect
	github.com/vmware-labs/yaml-jsonpath v0.3.2 // indirect
	github.com/woodsbury/decimal128 v1.4.0 // indirect
	go.yaml.in/yaml/v3 v3.0.4 // indirect
	golang.org/x/image v0.43.0 // indirect
	golang.org/x/mod v0.37.0 // indirect
	golang.org/x/sync v0.22.0 // indirect
	golang.org/x/sys v0.47.0 // indirect
	golang.org/x/text v0.40.0
	golang.org/x/tools v0.47.0
	gopkg.in/yaml.v3 v3.0.1 // indirect
	modernc.org/libc v1.74.1 // indirect
	modernc.org/mathutil v1.7.1 // indirect
	modernc.org/memory v1.11.0 // indirect
	modernc.org/sqlite v1.54.0
)

replace github.com/colespringer/waxdeck/fixtures => ../fixtures
