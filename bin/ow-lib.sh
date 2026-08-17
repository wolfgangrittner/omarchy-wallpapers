#!/bin/bash
# Shared checks for the values that arrive from Unsplash.
#
# Everything the panel hands these scripts — photo ids, image URLs, the
# download-ping endpoint — is read out of an API response body, so it is only
# as trustworthy as the API, DNS and whatever proxy sits between. An id ends up
# in a filename and a URL ends up in a transfer that may carry the access key,
# so both are checked against the shape they are allowed to have before they
# reach a path or a curl invocation.
#
# Sourced, never executed:  . "$(dirname "$0")/ow-lib.sh"

OW_API_HOST="api.unsplash.com"
OW_IMAGE_HOSTS=("images.unsplash.com" "plus.unsplash.com")
OW_LINK_HOSTS=("unsplash.com" "www.unsplash.com")

# Photo ids become "unsplash-<id>.jpg" in the theme background directory. Only
# the alphabet Unsplash actually uses is accepted, which leaves no way to reach
# a slash, a "..", or a leading dash.
ow_valid_id() {
  [[ ${1-} =~ ^[A-Za-z0-9_-]{1,128}$ ]]
}

# Access keys are alphanumeric with the occasional separator. Checked because
# the key is written into a curl config file, where a newline would start a new
# directive.
ow_valid_key() {
  [[ ${1-} =~ ^[A-Za-z0-9._-]{8,255}$ ]]
}

# https, an exact host from the given list, and nothing that could smuggle a
# different destination past that check: no userinfo ("https://images.unsplash.com@evil"),
# no port, no whitespace or quoting that a later shell or curl config would
# have to survive.
ow_url_host_in() {
  local url="${1-}"; shift
  local host rest

  [[ $url == https://* ]] || return 1
  [[ $url != *[[:space:][:cntrl:]\"\'\\]* ]] || return 1

  rest="${url#https://}"
  host="${rest%%[/?#]*}"
  [[ -n $host ]] || return 1
  [[ $host != *[@:]* ]] || return 1

  local allowed
  for allowed in "$@"; do
    [[ ${host,,} == "$allowed" ]] && return 0
  done
  return 1
}

ow_valid_image_url() { ow_url_host_in "${1-}" "${OW_IMAGE_HOSTS[@]}"; }
ow_valid_link_url() { ow_url_host_in "${1-}" "${OW_LINK_HOSTS[@]}"; }
ow_valid_api_url() { ow_url_host_in "${1-}" "$OW_API_HOST"; }

# Optional fields are recorded for the panel to render later. A value that
# fails its check is dropped rather than failing the run: losing a thumbnail
# URL is not worth refusing to set a wallpaper over. Both always succeed, so
# `x="$(ow_image_url_or_empty "$u")"` cannot trip `set -e`.
ow_image_url_or_empty() {
  if ow_valid_image_url "${1-}"; then printf '%s' "$1"; fi
  return 0
}

ow_link_url_or_empty() {
  if ow_valid_link_url "${1-}"; then printf '%s' "$1"; fi
  return 0
}
