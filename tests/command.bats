#!/usr/bin/env bats

setup() {
  load "${BATS_PLUGIN_PATH}/load.bash"

  # Set up common test environment
  export BUILDKITE_PLUGIN_OSSF_SCORECARD_GITHUB_TOKEN='test-token'
  export BUILDKITE_REPO='https://github.com/example/repo'
}

teardown() {
  unstub buildkite-agent 2>/dev/null || true
  unstub docker 2>/dev/null || true
  unstub jq 2>/dev/null || true
  unstub bc 2>/dev/null || true
  unstub which 2>/dev/null || true
}

@test "Missing github_token fails" {
  unset BUILDKITE_PLUGIN_OSSF_SCORECARD_GITHUB_TOKEN

  run "$PWD"/hooks/command

  assert_failure
  assert_output --partial "Missing required 'github_token' parameter"
}

@test "Missing repository URL fails" {
  unset BUILDKITE_REPO

  run "$PWD"/hooks/command

  assert_failure
  assert_output --partial "Unable to determine repository URL"
}

@test "Basic scorecard execution succeeds" {
  stub docker \
    "run --rm -e GITHUB_AUTH_TOKEN=test-token gcr.io/openssf/scorecard:stable --repo=https://github.com/example/repo --format=json : echo '{\"score\":7.5,\"checks\":[{\"name\":\"Binary-Artifacts\",\"score\":10,\"reason\":\"no binaries found\"}]}'"

  run "$PWD"/hooks/command

  assert_success
  assert_output --partial "Running OSSF Scorecard analysis"
  assert_output --partial "Repository: https://github.com/example/repo"
  assert_output --partial "OSSF Scorecard completed successfully"
}

@test "Custom format parameter works" {
  export BUILDKITE_PLUGIN_OSSF_SCORECARD_FORMAT='csv'

  stub docker \
    "run --rm -e GITHUB_AUTH_TOKEN=test-token gcr.io/openssf/scorecard:stable --repo=https://github.com/example/repo --format=csv : echo 'repo,date,commit,check,score'"

  run "$PWD"/hooks/command

  assert_success
  assert_output --partial "Format: csv"
}

@test "Custom version parameter works" {
  export BUILDKITE_PLUGIN_OSSF_SCORECARD_VERSION='v4.8.0'

  stub docker \
    "run --rm -e GITHUB_AUTH_TOKEN=test-token gcr.io/openssf/scorecard:v4.8.0 --repo=https://github.com/example/repo --format=json : echo '{\"score\":8.0,\"checks\":[{\"name\":\"License\",\"score\":10,\"reason\":\"license file detected\"}]}'"

  run "$PWD"/hooks/command

  assert_success
  assert_output --partial "Version: v4.8.0"
}

@test "Specific checks parameter works" {
  export BUILDKITE_PLUGIN_OSSF_SCORECARD_CHECKS_0='Binary-Artifacts'
  export BUILDKITE_PLUGIN_OSSF_SCORECARD_CHECKS_1='Code-Review'

  stub docker \
    "run --rm -e GITHUB_AUTH_TOKEN=test-token gcr.io/openssf/scorecard:stable --repo=https://github.com/example/repo --format=json --checks=Binary-Artifacts --checks=Code-Review : echo '{\"score\":6.0,\"checks\":[{\"name\":\"Binary-Artifacts\",\"score\":10,\"reason\":\"no binaries found\"},{\"name\":\"Code-Review\",\"score\":2,\"reason\":\"Found 1/12 approved changesets\"}]}'"

  run "$PWD"/hooks/command

  assert_success
  assert_output --partial "OSSF Scorecard completed successfully"
}

@test "Threshold check passes when score meets threshold" {
  export BUILDKITE_PLUGIN_OSSF_SCORECARD_FAIL_BUILD_THRESHOLD='5.0'

  stub which \
    "jq : exit 0" \
    "buildkite-agent : exit 1" \
    "jq : exit 0" \
    "awk : exit 0"
  stub docker \
    "run --rm -e GITHUB_AUTH_TOKEN=test-token gcr.io/openssf/scorecard:stable --repo=https://github.com/example/repo --format=json : echo '{\"score\":7.5}'"
  stub jq \
    "-r '.score // \"N/A\"' : echo '7.5'" \
    "-r '.score // 0' : echo '7.5'"
  stub bc \
    "-l : echo '0'"

  run "$PWD"/hooks/command

  assert_success
  assert_output --partial "Score 7.5 meets threshold 5.0"
}

@test "Threshold check fails when score below threshold" {
  export BUILDKITE_PLUGIN_OSSF_SCORECARD_FAIL_BUILD_THRESHOLD='8.0'

  stub which \
    "jq : exit 0" \
    "buildkite-agent : exit 1" \
    "jq : exit 0" \
    "awk : exit 0"
  stub docker \
    "run --rm -e GITHUB_AUTH_TOKEN=test-token gcr.io/openssf/scorecard:stable --repo=https://github.com/example/repo --format=json : echo '{\"score\":7.5}'"
  stub jq \
    "-r '.score // \"N/A\"' : echo '7.5'" \
    "-r '.score // 0' : echo '7.5'"
  stub bc \
    "-l : echo '1'"

  run "$PWD"/hooks/command

  assert_failure
  assert_output --partial "Build failed: Overall score 7.5 is below threshold 8.0"
}
