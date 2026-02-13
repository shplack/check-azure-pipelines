#!/usr/bin/env bash

# Check if AZURE_DEVOPS_PAT is set
if [[ -z "$AZURE_DEVOPS_PAT" ]]; then
  echo "Error: Environment variable AZURE_DEVOPS_PAT is not set."
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

  if command -v fzf > /dev/null; then
    # Use fzf for selection with prompt
    printf '%s\n' "${options[@]}" | fzf --prompt="$prompt> "
  else
    # Fallback to select menu
    echo "fzf not found, falling back to select menu."
    PS3="$prompt> "
    select opt in "${options[@]}"; do
      if [[ -n $opt ]]; then
        echo "$opt"
        break
      else
        echo "Invalid selection."
      fi
    done
  fi
}

# Parse input arguments or prompt for them
if [[ $# -eq 3 ]]; then
  ORG=$1
  PROJECT=$2
  PIPELINE_ID=$3
else
  # Check env vars for ORG, PROJECT, PIPELINE_ID
  ORG=${AZURE_DEVOPS_ORG:-}
  PROJECT=${AZURE_DEVOPS_PROJECT:-}
  PIPELINE_ID=${AZURE_DEVOPS_PIPELINE_ID:-}

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
      echo "No projects found in organization $ORG."
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
      echo "No pipelines found in project $PROJECT."
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
      echo "Failed to find pipeline ID for selected pipeline."
      exit 1
    fi
  fi
fi

# URL encode pipeline id is numeric, so no need

# Fetch the latest run status of the pipeline
runs_json=$(api_call "https://dev.azure.com/$ENC_ORG/$ENC_PROJECT/_apis/pipelines/$PIPELINE_ID/runs?api-version=7.0&\$top=1")

latest_run_id=$(echo "$runs_json" | jq -r '.value[0].id')
latest_run_status=$(echo "$runs_json" | jq -r '.value[0].state')
latest_run_result=$(echo "$runs_json" | jq -r '.value[0].result')
latest_run_url=$(echo "$runs_json" | jq -r '.value[0]._links.web.href')

if [[ "$latest_run_id" == "null" ]]; then
  echo "No runs found for pipeline ID $PIPELINE_ID."
  exit 1
fi

echo "Pipeline: $PIPELINE_ID"
echo "Latest run ID: $latest_run_id"
echo "Status: $latest_run_status"
echo "Result: $latest_run_result"
echo "URL: $latest_run_url"
