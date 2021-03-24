PROJECT = hvac_iot
PROJECT_DESCRIPTION = New project
PROJECT_VERSION = 0.1.0

DEPS = \
	emqtt
BUILD_DEPS = \
	version.mk \
	erlfmt


dep_emqtt = git https://github.com/emqx/emqtt.git v1.2.3
dep_erlfmt = git https://github.com/WhatsApp/erlfmt.git v0.8.0
dep_version.mk = git https://github.com/manifest/version.mk.git v0.2.0

SHELL_OPTS = -eval 'application:ensure_all_started(hvac_iot).' -config sys +S2

erlfmt:
	$(gen_verbose) $(SHELL_ERL) -pa $(SHELL_PATHS) -eval 'erlfmt_cli:do("erlfmt", [write, {files, ["src/*.erl", "tests/*.erl"]} ]), halt(0)'

erlfmt_check:
	$(gen_verbose) $(SHELL_ERL) -pa $(SHELL_PATHS) -eval 'erlfmt_cli:do("erlfmt", [check, {files, ["src/*.erl", "tests/*.erl"]} ]), halt(0)'

include erlang.mk
