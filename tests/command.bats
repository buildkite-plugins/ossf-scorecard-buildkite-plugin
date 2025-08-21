#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

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
  export BUILDKITE_PLUGIN_OSSF_SCORECARD_ANNOTATE='false'

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
  export BUILDKITE_PLUGIN_OSSF_SCORECARD_ANNOTATE='false'

  stub which \
    "jq : exit 0" \
    "bc : exit 0"
  stub docker \
    "run --rm -e GITHUB_AUTH_TOKEN=test-token gcr.io/openssf/scorecard:stable --repo=https://github.com/example/repo --format=json : echo '{\"score\":7.5}'"
  stub jq \
    "-r '.score // 0' : echo '7.5'"
  stub bc \
    "-l : echo '0'"

  run "$PWD"/hooks/command

  assert_success
  assert_output --partial "Score 7.5 meets threshold 5.0"
}

@test "Threshold check fails when score below threshold" {
  export BUILDKITE_PLUGIN_OSSF_SCORECARD_FAIL_BUILD_THRESHOLD='8.0'
  export BUILDKITE_PLUGIN_OSSF_SCORECARD_ANNOTATE='false'

  stub which \
    "jq : exit 0" \
    "bc : exit 0"
  stub docker \
    "run --rm -e GITHUB_AUTH_TOKEN=test-token gcr.io/openssf/scorecard:stable --repo=https://github.com/example/repo --format=json : echo '{\"score\":7.5}'"
  stub jq \
    "-r '.score // 0' : echo '7.5'"
  stub bc \
    "-l : echo '1'"

  run "$PWD"/hooks/command

  assert_failure
  assert_output --partial "Build failed: Overall score 7.5 is below threshold 8.0"
}

@test "Enhanced annotation with high score shows success style" {
  export BUILDKITE_PLUGIN_OSSF_SCORECARD_ANNOTATE='true'

  stub which \
    "jq : exit 0" \
    "buildkite-agent : exit 1"
  stub docker \
    "run --rm -e GITHUB_AUTH_TOKEN=test-token gcr.io/openssf/scorecard:stable --repo=https://github.com/example/repo --format=json : echo '{\"score\":8.5,\"checks\":[{\"name\":\"Code-Review\",\"score\":10,\"reason\":\"Found 25/25 approved changesets\"},{\"name\":\"Binary-Artifacts\",\"score\":10,\"reason\":\"no binaries found\"},{\"name\":\"Maintained\",\"score\":5,\"reason\":\"5 commits in last 90 days\"}]}'"
  stub jq \
    "-r '.score // \"N/A\"' : echo '8.5'" \
    "-r '.checks | length' : echo '3'" \
    "-r '[.checks[] | select(.score >= 7)] | length' : echo '2'" \
    "-r '[.checks[] | select(.score >= 4 and .score < 7)] | length' : echo '1'" \
    "-r '[.checks[] | select(.score < 4 and .score >= 0)] | length' : echo '0'" \
    "-r '[.checks[] | select(.score < 0)] | length' : echo '0'" \
    "-r '[.checks[] | select(.score >= 0)] | sort_by(-.score) | .[0:3] | .[] | \"• **\\(.name)**: \\(.score)/10 - \\(.reason)\"' : echo '• **Code-Review**: 10/10 - Found 25/25 approved changesets\n• **Binary-Artifacts**: 10/10 - no binaries found\n• **Maintained**: 5/10 - 5 commits in last 90 days'" \
    "-r '[.checks[] | select(.score < 7 and .score >= 0)] | sort_by(.score) | .[0:3] | .[] | \"• **\\(.name)**: \\(.score)/10 - \\(.reason)\"' : echo '• **Maintained**: 5/10 - 5 commits in last 90 days'" \
    "-r '[.checks[] | select(.score < 0)] | .[] | \"• **\\(.name)**: Error - \\(.reason)\"' : echo ''"
  stub bc \
    "-l : echo '1'" \
    "-l : echo '0'" \
    "-l : echo '0'"

  run "$PWD"/hooks/command

  assert_success
  assert_output --partial "Enhanced annotation content prepared (buildkite-agent not available)"
}

@test "Enhanced annotation with medium score shows warning style" {
  export BUILDKITE_PLUGIN_OSSF_SCORECARD_ANNOTATE='true'

  stub which \
    "jq : exit 0" \
    "buildkite-agent : exit 1"
  stub docker \
    "run --rm -e GITHUB_AUTH_TOKEN=test-token gcr.io/openssf/scorecard:stable --repo=https://github.com/example/repo --format=json : echo '{\"score\":6.5,\"checks\":[{\"name\":\"Code-Review\",\"score\":8,\"reason\":\"Found 20/25 approved changesets\"},{\"name\":\"SAST\",\"score\":0,\"reason\":\"no SAST tool detected\"},{\"name\":\"Branch-Protection\",\"score\":-1,\"reason\":\"internal error\"}]}'"
  stub jq \
    "-r '.score // \"N/A\"' : echo '6.5'" \
    "-r '.checks | length' : echo '3'" \
    "-r '[.checks[] | select(.score >= 7)] | length' : echo '1'" \
    "-r '[.checks[] | select(.score >= 4 and .score < 7)] | length' : echo '0'" \
    "-r '[.checks[] | select(.score < 4 and .score >= 0)] | length' : echo '1'" \
    "-r '[.checks[] | select(.score < 0)] | length' : echo '1'" \
    "-r '[.checks[] | select(.score >= 0)] | sort_by(-.score) | .[0:3] | .[] | \"• **\\(.name)**: \\(.score)/10 - \\(.reason)\"' : echo '• **Code-Review**: 8/10 - Found 20/25 approved changesets\n• **SAST**: 0/10 - no SAST tool detected'" \
    "-r '[.checks[] | select(.score < 7 and .score >= 0)] | sort_by(.score) | .[0:3] | .[] | \"• **\\(.name)**: \\(.score)/10 - \\(.reason)\"' : echo '• **SAST**: 0/10 - no SAST tool detected'" \
    "-r '[.checks[] | select(.score < 0)] | .[] | \"• **\\(.name)**: Error - \\(.reason)\"' : echo '• **Branch-Protection**: Error - internal error'"
  stub bc \
    "-l : echo '0'" \
    "-l : echo '1'" \
    "-l : echo '1'"

  run "$PWD"/hooks/command

  assert_success
  assert_output --partial "Enhanced annotation content prepared (buildkite-agent not available)"
}

@test "Enhanced annotation with low score shows error style" {
  export BUILDKITE_PLUGIN_OSSF_SCORECARD_ANNOTATE='true'

  stub which \
    "jq : exit 0" \
    "buildkite-agent : exit 1"
  stub docker \
    "run --rm -e GITHUB_AUTH_TOKEN=test-token gcr.io/openssf/scorecard:stable --repo=https://github.com/example/repo --format=json : echo '{\"score\":3.2,\"checks\":[{\"name\":\"SAST\",\"score\":0,\"reason\":\"no SAST tool detected\"},{\"name\":\"Code-Review\",\"score\":2,\"reason\":\"Found 2/25 approved changesets\"},{\"name\":\"Vulnerabilities\",\"score\":8,\"reason\":\"no vulnerabilities detected\"}]}'"
  stub jq \
    "-r '.score // \"N/A\"' : echo '3.2'" \
    "-r '.checks | length' : echo '3'" \
    "-r '[.checks[] | select(.score >= 7)] | length' : echo '1'" \
    "-r '[.checks[] | select(.score >= 4 and .score < 7)] | length' : echo '0'" \
    "-r '[.checks[] | select(.score < 4 and .score >= 0)] | length' : echo '2'" \
    "-r '[.checks[] | select(.score < 0)] | length' : echo '0'" \
    "-r '[.checks[] | select(.score >= 0)] | sort_by(-.score) | .[0:3] | .[] | \"• **\\(.name)**: \\(.score)/10 - \\(.reason)\"' : echo '• **Vulnerabilities**: 8/10 - no vulnerabilities detected\n• **Code-Review**: 2/10 - Found 2/25 approved changesets\n• **SAST**: 0/10 - no SAST tool detected'" \
    "-r '[.checks[] | select(.score < 7 and .score >= 0)] | sort_by(.score) | .[0:3] | .[] | \"• **\\(.name)**: \\(.score)/10 - \\(.reason)\"' : echo '• **SAST**: 0/10 - no SAST tool detected\n• **Code-Review**: 2/10 - Found 2/25 approved changesets'" \
    "-r '[.checks[] | select(.score < 0)] | .[] | \"• **\\(.name)**: Error - \\(.reason)\"' : echo ''"
  stub bc \
    "-l : echo '0'" \
    "-l : echo '0'" \
    "-l : echo '1'"

  run "$PWD"/hooks/command

  assert_success
  assert_output --partial "Enhanced annotation content prepared (buildkite-agent not available)"
}
