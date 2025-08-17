#!/bin/bash
set -o pipefail

# Set path to this script
SCRIPTPATH="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# Get script's name
SCRIPTNAME="${BASH_SOURCE[0]##*/}"

check_and_update() {
  # Get inside the git repo directory
  cd "${SCRIPTPATH}"/.. || exit
  # Get the branch currently used
  CURBRANCH=$(git rev-parse --abbrev-ref HEAD)
  # Get latest updates to the repo
  git fetch --all && \
  git reset --hard origin/"${CURBRANCH}"

  # Get latest release of webhook and release used in this repo
  LATEST_RELEASE=$(curl -sf https://api.github.com/repos/adnanh/webhook/releases/latest | \
    jq -r '.tag_name // empty' 2>/dev/null || \
    curl -s https://api.github.com/repos/adnanh/webhook/releases/latest | \
    grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4)
  LOCAL_RELEASE=$(grep "^ENV.*WEBHOOK_VERSION" "${SCRIPTPATH}"/../Dockerfile | awk -F '=' '{ print $2 }')

  # Compare releases and update Dockerfile in case they differ
  if [[ "${LOCAL_RELEASE}" != "${LATEST_RELEASE}" ]] && [[ -n ${LATEST_RELEASE} ]]; then
    # Update the Dockerfile with new version
    sed -i "s/WEBHOOK_VERSION=${LOCAL_RELEASE}/WEBHOOK_VERSION=${LATEST_RELEASE}/g" "${SCRIPTPATH}"/../Dockerfile

    # Commit and push changes
    git add "${SCRIPTPATH}"/../Dockerfile
    git commit -m "- bump webhook version to ${LATEST_RELEASE}"

    # Push and create release if credentials are provided
    if [[ -n ${GITHUB_USER} ]] && [[ -n ${GITHUB_TOKEN} ]]; then
      git push origin "${CURBRANCH}" && \
      curl -s -X POST -H "Content-Type: application/json" \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        -d '{"tag_name":"'"${LATEST_RELEASE}"'","target_commitish":"'"${CURBRANCH}"'","name":"webhook '"${LATEST_RELEASE}"'","body":"Release for webhook version '"${LATEST_RELEASE}"'.","draft":false,"prerelease":false}' \
        https://api.github.com/repos/${GITHUB_USER}/docker-webhook/releases
    else
      git push origin "${CURBRANCH}"
      echo "GitHub credentials not provided - skipping release creation"
    fi

    echo "Updated webhook version from ${LOCAL_RELEASE} to ${LATEST_RELEASE}"
  else
    echo "Webhook version is up to date (${LOCAL_RELEASE})"
  fi
}

argmissing() {
  echo "Usage: $0 [--user GITHUB_USERNAME] [--token GITHUB_TOKEN] [--write-crontab]"
  echo
  echo "Switches:"
  echo -e "\t--user\t\t\tSpecify GitHub username - optional (required for release creation)."
  echo -e "\t--token\t\t\tSpecify GitHub personal access token - optional (required for release creation)."
  echo -e "\t--write-crontab\t\tAdd crontab entry for this script - optional."
  echo
  echo "Examples:"
  echo -e "\t$0"
  echo -e "\t$0 --user someuser --token ghp_sometoken"
  echo -e "\t$0 --user someuser --token ghp_sometoken --write-crontab"
  echo -e "\t$0 --write-crontab"
  echo
  echo "Note: GitHub credentials are only needed for automatic release creation."
  echo "      The script will still update the Dockerfile without them."
  exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --user)
      GITHUB_USER="$2"
      shift 2
      ;;
    --token)
      GITHUB_TOKEN="$2"
      shift 2
      ;;
    --write-crontab)
      WRITE_CRONTAB=true
      shift
      ;;
    --help|-h)
      argmissing
      ;;
    *)
      echo "Unknown option: $1"
      argmissing
      ;;
  esac
done

# Handle crontab creation
if [[ "${WRITE_CRONTAB}" == "true" ]]; then
  if ! crontab -l 2>/dev/null | grep -q "${SCRIPTNAME}"; then
    echo "Creating crontab entry."
    CRON_CMD="${SCRIPTPATH}/${SCRIPTNAME}"
    if [[ -n ${GITHUB_USER} ]] && [[ -n ${GITHUB_TOKEN} ]]; then
      CRON_CMD="${CRON_CMD} --user ${GITHUB_USER} --token ${GITHUB_TOKEN}"
    fi
    (crontab -l 2>/dev/null; echo -e "# Check for webhook releases every five minutes\n*/5 * * * * ${CRON_CMD} > /dev/null 2>&1") | crontab -
    echo "Crontab entry created successfully."
  else
    echo "Crontab entry already exists."
  fi
fi

# Run the main function
check_and_update

exit 0
