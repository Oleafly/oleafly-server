#!/bin/sh
set -u

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)
workflow=$repo/.github/workflows/sync-release.yml
work=$(mktemp -d)
FIX=$work/fix
export FIX
passed=0
failed=0
failures=
status=

if ! python3 -c 'import yaml' 2>/dev/null || ! command -v jq >/dev/null 2>&1; then
	apt-get update -qq >/dev/null
	DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-yaml jq >/dev/null 2>&1
fi

python3 - "$workflow" >"$work/sync.sh" <<'PY' || {
import sys
import yaml

workflow = yaml.safe_load(open(sys.argv[1]))
for step in workflow["jobs"]["sync"]["steps"]:
    if step.get("name") == "Copy new server releases from Oleafly/Oleafly":
        sys.stdout.write(step["run"])
        sys.exit(0)
sys.exit(1)
PY
	echo "the workflow has no 'Copy new server releases from Oleafly/Oleafly' step"
	exit 1
}

release_assets() {
	tag=$1
	version=${tag#server-v}
	dir=$FIX/assets/$tag
	mkdir -p "$dir"
	printf '#!/bin/sh\nset -eu\n\ninstaller_version=%s\n' "$version" >"$dir/install.sh"
	printf 'services:\n  oleafly-server:\n    image: ghcr.io/oleafly/oleafly-server:%s\n  caddy:\n    image: caddy:2.11.7\n' "$version" >"$dir/docker-compose.yml"
	printf '{%sOLEAFLY_DOMAIN} {\n\treverse_proxy oleafly-server:8080\n}\n' '$' >"$dir/Caddyfile"
	printf 'OLEAFLY_DOMAIN=collab.example.org\n' >"$dir/env.example"
	printf 'dbs:\n  - path: /data/oleafly-server.sqlite3\n' >"$dir/litestream.yml"
	printf 'archive\n' >"$dir/oleafly-server-$version-x86_64-unknown-linux-musl.tar.gz"
	(cd "$dir" && sha256sum -- *.tar.gz install.sh docker-compose.yml Caddyfile env.example litestream.yml >SHA256SUMS)
	rm "$dir/oleafly-server-$version-x86_64-unknown-linux-musl.tar.gz"
}

source_releases() {
	printf '[' >"$FIX/source.json"
	separator=
	for entry in "$@"; do
		tag=${entry%:*}
		draft=${entry#*:}
		printf '%s{"tag_name": "%s", "draft": %s}' "$separator" "$tag" "$draft" >>"$FIX/source.json"
		separator=', '
		release_assets "$tag"
	done
	printf ']\n' >>"$FIX/source.json"
}

target_releases() {
	printf '[' >"$FIX/target.json"
	separator=
	for tag in "$@"; do
		printf '%s{"tag_name": "%s"}' "$separator" "$tag" >>"$FIX/target.json"
		separator=', '
	done
	printf ']\n' >>"$FIX/target.json"
}

begin() {
	scenario=$1
	scenario_failed=0
	rm -rf "$FIX"
	mkdir -p "$FIX/created"
	: >"$FIX/log"
	: >"$FIX/order"
}

run_sync() {
	env PATH="$here/stubs:$PATH" FIX="$FIX" GH_TOKEN=token SOURCE_REPO=Oleafly/Oleafly TARGET_REPO=Oleafly/oleafly-server \
		GITHUB_SHA=0123456789abcdef GITHUB_STEP_SUMMARY="$FIX/summary" TAG="${1:-}" bash "$work/sync.sh" >"$work/out" 2>&1
	status=$?
}

expect() {
	description=$1
	shift
	if ! "$@"; then
		scenario_failed=1
		printf '    expected: %s\n' "$description"
	fi
}

out_has() {
	grep -qF -- "$1" "$work/out"
}

created() {
	[ -d "$FIX/created/$1" ]
}

args_have() {
	grep -qF -- "$2" "$FIX/created/$1/args"
}

finish() {
	if [ "$scenario_failed" = 0 ]; then
		passed=$((passed + 1))
		printf 'ok   %s\n' "$scenario"
	else
		failed=$((failed + 1))
		failures="$failures
  $scenario"
		printf 'FAIL %s\n' "$scenario"
		sed 's/^/    | /' "$work/out"
	fi
}

begin "copies a new published release and skips drafts"
source_releases server-v0.1.0:false server-v0.2.0:true
target_releases
run_sync
expect "exit 0, got $status" [ "$status" = 0 ]
expect "the published release is created" created server-v0.1.0
expect "the draft is not" sh -c "[ ! -d '$FIX/created/server-v0.2.0' ]"
expect "it is marked latest" args_have server-v0.1.0 '--latest'
expect "it is not marked latest=false" sh -c "! grep -q -- '--latest=false' '$FIX/created/server-v0.1.0/args'"
expect "it is tagged on this commit" args_have server-v0.1.0 '--target 0123456789abcdef'
expect "it has the right title" args_have server-v0.1.0 '--title Oleafly Server 0.1.0'
expect "all six files are uploaded" [ "$(sort "$FIX/created/server-v0.1.0/files" | paste -sd ' ' -)" = 'Caddyfile SHA256SUMS docker-compose.yml env.example install.sh litestream.yml' ]
expect "the notes have the install command" grep -qxF 'curl -fsSL https://oleafly.com/server/install.sh | sudo sh' "$FIX/created/server-v0.1.0/notes"
expect "the notes link the source release" grep -qF 'https://github.com/Oleafly/Oleafly/releases/tag/server-v0.1.0' "$FIX/created/server-v0.1.0/notes"
expect "the notes avoid semicolons" sh -c "! grep -q ';' '$FIX/created/server-v0.1.0/notes'"
expect "the summary says so" grep -qF 'Copied server-v0.1.0 from Oleafly/Oleafly.' "$FIX/summary"
finish

begin "does nothing when the release is already here"
source_releases server-v0.1.0:false
target_releases server-v0.1.0
run_sync
expect "exit 0, got $status" [ "$status" = 0 ]
expect "nothing is created" [ -z "$(ls "$FIX/created")" ]
expect "it says so" out_has 'server-v0.1.0 is already here.'
expect "nothing is downloaded" sh -c "! grep -q 'release download' '$FIX/log'"
finish

begin "does nothing when no release is published yet"
source_releases server-v0.1.0:true
target_releases
run_sync
expect "exit 0, got $status" [ "$status" = 0 ]
expect "nothing is created" [ -z "$(ls "$FIX/created")" ]
expect "it says so" out_has 'No published server releases in Oleafly/Oleafly yet.'
finish

begin "does nothing when the source has no releases at all"
printf '[]\n' >"$FIX/source.json"
target_releases
run_sync
expect "exit 0, got $status" [ "$status" = 0 ]
expect "it says so" out_has 'No published server releases in Oleafly/Oleafly yet.'
finish

begin "ignores other tags in the source repository"
source_releases v0.4.6:false server-v0.1.0:false
target_releases
run_sync
expect "exit 0, got $status" [ "$status" = 0 ]
expect "the app release is not copied" sh -c "[ ! -d '$FIX/created/v0.4.6' ]"
expect "the server release is copied" created server-v0.1.0
finish

begin "refuses a file that doesn't match SHA256SUMS and copies nothing"
source_releases server-v0.1.0:false
target_releases
echo tampered >>"$FIX/assets/server-v0.1.0/Caddyfile"
run_sync
expect "a failure, got $status" [ "$status" != 0 ]
expect "the file is named" out_has "::error::Caddyfile in server-v0.1.0 doesn't match SHA256SUMS"
expect "nothing is created" [ -z "$(ls "$FIX/created")" ]
finish

begin "refuses a release without one of the files"
source_releases server-v0.1.0:false
target_releases
rm "$FIX/assets/server-v0.1.0/litestream.yml"
run_sync
expect "a failure, got $status" [ "$status" != 0 ]
expect "the file is named" out_has '::error::server-v0.1.0 in Oleafly/Oleafly has no litestream.yml'
expect "nothing is created" [ -z "$(ls "$FIX/created")" ]
finish

begin "refuses an installer that isn't stamped with the release's version"
source_releases server-v0.1.0:false
target_releases
sed -i 's/^installer_version=.*/installer_version=unreleased/' "$FIX/assets/server-v0.1.0/install.sh"
(cd "$FIX/assets/server-v0.1.0" && sha256sum install.sh docker-compose.yml Caddyfile env.example litestream.yml >SHA256SUMS)
run_sync
expect "a failure, got $status" [ "$status" != 0 ]
expect "the problem is named" out_has "::error::install.sh in server-v0.1.0 isn't stamped with 0.1.0"
finish

begin "refuses a compose file for another version"
source_releases server-v0.1.0:false
target_releases
sed -i 's/oleafly-server:0.1.0/oleafly-server:0.0.9/' "$FIX/assets/server-v0.1.0/docker-compose.yml"
(cd "$FIX/assets/server-v0.1.0" && sha256sum install.sh docker-compose.yml Caddyfile env.example litestream.yml >SHA256SUMS)
run_sync
expect "a failure, got $status" [ "$status" != 0 ]
expect "the problem is named" out_has "::error::docker-compose.yml in server-v0.1.0 doesn't use the 0.1.0 server image"
finish

begin "copies several new releases oldest first and marks only the newest as latest"
source_releases server-v0.1.1:false server-v0.1.0:false server-v0.1.10:false
target_releases
run_sync
expect "exit 0, got $status" [ "$status" = 0 ]
expect "they are created in version order" [ "$(paste -sd ' ' "$FIX/order")" = 'server-v0.1.0 server-v0.1.1 server-v0.1.10' ]
expect "0.1.0 is not latest" args_have server-v0.1.0 '--latest=false'
expect "0.1.1 is not latest" args_have server-v0.1.1 '--latest=false'
expect "0.1.10 is latest" sh -c "grep -q -- '--latest\$\\|--latest ' '$FIX/created/server-v0.1.10/args' && ! grep -q -- '--latest=false' '$FIX/created/server-v0.1.10/args'"
expect "it counts them" out_has '3 new release(s) copied.'
finish

begin "a chosen older tag is copied without becoming latest"
source_releases server-v0.1.0:false server-v0.2.0:false
target_releases server-v0.2.0
run_sync server-v0.1.0
expect "exit 0, got $status" [ "$status" = 0 ]
expect "only that tag is created" [ "$(ls "$FIX/created")" = server-v0.1.0 ]
expect "it is not latest" args_have server-v0.1.0 '--latest=false'
finish

begin "a prerelease is copied as a prerelease"
source_releases server-v0.1.0:false server-v0.2.0-rc.1:false
target_releases server-v0.1.0
run_sync
expect "exit 0, got $status" [ "$status" = 0 ]
expect "it is a prerelease" args_have server-v0.2.0-rc.1 '--prerelease --latest=false'
finish

begin "a chosen tag must be published"
source_releases server-v0.1.0:false server-v0.2.0:true
target_releases
run_sync server-v0.2.0
expect "a failure, got $status" [ "$status" != 0 ]
expect "it says why" out_has "::error::server-v0.2.0 is not a published release in Oleafly/Oleafly. Drafts don't count."
expect "nothing is created" [ -z "$(ls "$FIX/created")" ]
finish

begin "a chosen tag must look like a server tag"
source_releases server-v0.1.0:false
target_releases
run_sync v0.1.0
expect "a failure, got $status" [ "$status" != 0 ]
expect "it says why" out_has "::error::'v0.1.0' is not a server tag such as server-v0.1.0"
finish

rm -rf "$work"
printf '\n%s passed, %s failed\n' "$passed" "$failed"
if [ "$failed" -gt 0 ]; then
	printf 'Failed:%s\n' "$failures"
	exit 1
fi
