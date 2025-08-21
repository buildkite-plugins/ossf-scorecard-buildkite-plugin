# OSSF Scorecard Buildkite Plugin [![Build status](https://badge.buildkite.com/d673030645c7f3e7e397affddd97cfe9f93a40547ed17b6dc5.svg)](https://buildkite.com/buildkite/plugins-template)

A Buildkite plugin that runs [OSSF Scorecard](https://github.com/ossf/scorecard) security analysis on your repository and provides detailed annotations with actionable insights.

## Features

- 🔍 **Comprehensive Security Analysis**: Runs OSSF Scorecard checks on your repository
- 📊 **Rich Annotations**: Creates detailed Buildkite annotations with:
  - Overall security score with visual indicators
  - Summary of passed/failed/warning checks
  - Top performing and worst performing security checks
  - Actionable recommendations based on your score
  - Links to detailed documentation
- 🎯 **Build Failure Thresholds**: Optionally fail builds if security score is below a threshold
- 📁 **Artifact Storage**: Save detailed results as build artifacts

## Requirements

- Docker available on the build agent
- GitHub token with repository read access
- `jq` and `bc` for enhanced annotations (optional, gracefully degrades)

## Options

### Required

#### `github_token` (string)

GitHub token for accessing repository data. Can be a literal token or environment variable reference (e.g., `$GITHUB_TOKEN`).

### Optional

#### `annotate` (boolean, default: `true`)

Whether to create a Buildkite annotation with detailed results.

#### `fail_build_threshold` (number)

Minimum score required to pass the build. If the overall score is below this threshold, the build will fail.

#### `format` (string, default: `json`)

Output format for scorecard results. Supported values: `json`, `csv`, `sarif`.

**Note:** Annotations are only created for JSON format.

#### `store_results` (boolean, default: `false`)

Whether to store the scorecard results as a build artifact.

#### `version` (string, default: `stable`)

OSSF Scorecard Docker image version to use.

#### `checks` (array)

Specific scorecard checks to run. If not specified, all checks are run.

## Examples

### Basic usage

```yaml
steps:
  - label: "🔍 Security Analysis"
    plugins:
      - ossf-scorecard#v1.0.1:
          github_token: "$GITHUB_TOKEN"
```

### With build failure threshold and artifact storage

```yaml
steps:
  - label: "🔍 Security Analysis"
    plugins:
      - ossf-scorecard#v1.0.1:
          github_token: "$GITHUB_TOKEN"
          fail_build_threshold: 7.0
          store_results: true
```

### Running specific checks only

```yaml
steps:
  - label: "🔍 Security Analysis"
    plugins:
      - ossf-scorecard#v1.0.1:
          github_token: "$GITHUB_TOKEN"
          checks:
            - "Binary-Artifacts"
            - "Code-Review"
            - "Vulnerabilities"
            - "SAST"
```

### CSV output without annotations

```yaml
steps:
  - label: "🔍 Security Analysis"
    plugins:
      - ossf-scorecard#v1.0.1:
          github_token: "$GITHUB_TOKEN"
          format: "csv"
          annotate: false
          store_results: true
```

### With all options set

```yaml
steps:
  - label: "🔍 Security Analysis"
    plugins:
      - ossf-scorecard#v1.0.1:
          github_token: "$GITHUB_TOKEN"
          format: "json"
          annotate: true
          fail_build_threshold: 7.0
          store_results: true
          version: "stable"
          checks:
            - "Binary-Artifacts"
            - "Vulnerabilities"
```

## Compatibility

| Elastic Stack | Agent Stack K8s | Hosted (Mac) | Hosted (Linux) | Notes |
| :-----------: | :-------------: | :----: | :----: |:---- |
| ✅ | ✅ | ❌ | ✅ | Hosted (Mac): Docker required to run tests |

### Running Tests

```bash
docker-compose run tests
```

### Linting

```bash
shellcheck hooks/** lib/** tests/**
```

## 👩‍💻 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## 📜 License

The package is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
