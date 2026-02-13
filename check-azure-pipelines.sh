#!/usr/bin/env bash

# This script checks the status of the latest run of an Azure DevOps pipeline.
# It requires the AZURE_DEVOPS_PAT environment variable to be set with a Personal Access Token.
# It can take optional arguments for organization, project, and pipeline ID, or it will prompt the user to select them interactively.

usage() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Checks the status of the latest run of an Azure DevOps pipeline."
  echo "Requires AZURE_DEVOPS_PAT environment variable to be set."
  echo ""
  echo "Optional arguments:"
  echo "  -o, --org <ORG>                 Azure DevOps Organization"
  echo "  -p, --project <PROJECT>         Azure DevOps Project"
  echo "  -i, --pipeline-id <PIPELINE_ID> Pipeline ID"
  echo "  -q, --quiet                     Suppress output, only return exit code (0 for success, 1 for failure)"
  echo "  -h, --help                      Show this help message"
}

if [[ -f ".env" ]]; then
  # read each line of .env and export it as an environment variable
  while IFS= read -r line || [[ -n "$line" ]]; do
    # skip empty lines and comments
    if [[ -z "$line" || "$line" == \#* ]]; then
      continue
    fi
    export "${line?}"
  done < ".env"
fi

# Set default values
QUIET=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -q|--quiet)
      QUIET=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -o|--org)
      ORG="$2"
      shift 2
      ;;
    -p|--project)
      PROJECT="$2"
      shift 2
      ;;
    -i|--pipeline-id)
      PIPELINE_ID="$2"
      shift 2
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

# Function to log messages only if not in quiet mode
log() {
  if [[ "$QUIET" = false ]]; then
    echo "$@"
  fi
}

# Check if AZURE_DEVOPS_PAT is set
if [[ -z "$AZURE_DEVOPS_PAT" ]]; then
  log "Error: Environment variable AZURE_DEVOPS_PAT is not set."
  exit 1
fi

if ! command -v fzf &> /dev/null; then
  log "Error: fzf is not installed. Please install fzf to use this script."
  exit 1
fi

if ! command -v jq &> /dev/null; then
  log "Error: jq is not installed. Please install jq to use this script."
  exit 1
fi

# URL encode helper function
urlencode() {
  local length="${#1}"
  local i
  for (( i = 0; i < length; i++ )); do
    local c="${1:i:1}"
    case $c in
      [a-zA-Z0-9.~_-]) printf '%s' "$c" ;;
      *) printf '%%%02X' "'$c" ;;
    esac
  done
}

# Function to make authenticated API calls
api_call() {
  local url=$1
  curl -sS -u :"$AZURE_DEVOPS_PAT" "$url" -H "Accept: application/json"
}

# Function to select from a list with arrow keys using fzf or fallback to select
select_from_list() {
  local prompt=$1
  shift
  local options=("$@")

  # Use fzf for selection with prompt
  printf '%s\n' "${options[@]}" | fzf --prompt="$prompt> "
}


# Check env vars for ORG, PROJECT, PIPELINE_ID
if [[ -z "$ORG" ]]; then
  ORG=${AZURE_DEVOPS_ORG:-}
fi

if [[ -z "$PROJECT" ]]; then
  PROJECT=${AZURE_DEVOPS_PROJECT:-}
fi

if [[ -z "$PIPELINE_ID" ]]; then
  PIPELINE_ID=${AZURE_DEVOPS_PIPELINE_ID:-}
fi

# Prompt for org if not set
if [[ -z "$ORG" ]]; then
  read -rp "Enter Azure DevOps organization name: " ORG
fi

# URL encode org for API calls
ENC_ORG=$(urlencode "$ORG")

# List projects and select if PROJECT not set
if [[ -z "$PROJECT" ]]; then
  projects_json=$(api_call "https://dev.azure.com/$ENC_ORG/_apis/projects?api-version=7.0")
  mapfile -t projects < <(echo "$projects_json" | jq -r '.value[].name')

  if [[ ${#projects[@]} -eq 0 ]]; then
    log "No projects found in organization $ORG."
    exit 1
  fi

  PROJECT=$(select_from_list "Select project" "${projects[@]}")
fi

# URL encode project for API calls
ENC_PROJECT=$(urlencode "$PROJECT")

# List pipelines and select if PIPELINE_ID not set
if [[ -z "$PIPELINE_ID" ]]; then
  pipelines_json=$(api_call "https://dev.azure.com/$ENC_ORG/$ENC_PROJECT/_apis/pipelines?api-version=7.0")
  mapfile -t pipeline_names < <(echo "$pipelines_json" | jq -r '.value[].name')
  mapfile -t pipeline_ids < <(echo "$pipelines_json" | jq -r '.value[].id')

  if [[ ${#pipeline_names[@]} -eq 0 ]]; then
    log "No pipelines found in project $PROJECT."
    exit 1
  fi

  selected_pipeline=$(select_from_list "Select pipeline" "${pipeline_names[@]}")

  # Find pipeline id by name
  PIPELINE_ID=""
  for i in "${!pipeline_names[@]}"; do
    if [[ "${pipeline_names[$i]}" == "$selected_pipeline" ]]; then
      PIPELINE_ID=${pipeline_ids[$i]}
      break
    fi
  done

  if [[ -z "$PIPELINE_ID" ]]; then
    log "Failed to find pipeline ID for selected pipeline."
    exit 1
  fi
fi

# Fetch the latest run status of the pipeline
runs_json=$(api_call "https://dev.azure.com/$ENC_ORG/$ENC_PROJECT/_apis/pipelines/$PIPELINE_ID/runs?api-version=7.0&\$top=1")

latest_run_id=$(log "$runs_json" | jq -r '.value[0].id')
latest_run_status=$(log "$runs_json" | jq -r '.value[0].state')
latest_run_result=$(log "$runs_json" | jq -r '.value[0].result')
latest_run_url=$(log "$runs_json" | jq -r '.value[0]._links.web.href')

if [[ "$latest_run_id" == "null" ]]; then
  log "No runs found for pipeline ID $PIPELINE_ID."
  exit 1
fi

log "Pipeline: $PIPELINE_ID"
log "Latest run ID: $latest_run_id"
log "Status: $latest_run_status"
log "Result: $latest_run_result"
log "URL: $latest_run_url"

if grep -q "succeeded" <<< "$latest_run_result"; then
  exit 0
else
  exit 1
fi
