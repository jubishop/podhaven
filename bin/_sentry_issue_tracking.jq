# The GitHub issues among an array of REST issue objects that track Sentry
# error issue $id, canonical first: open before closed, marker before link,
# then newest. Each gains `match` ("marker" or "link") and `analyzed`.
def sentry_issue_tracking($id):
  ("<!-- sentry-issue:" + $id + " -->") as $marker
  | ("https?://(artisanal-software[.])?sentry[.]io/(organizations/artisanal-software/)?issues/"
      + $id + "([/?#[:space:]<>)]|$)") as $link
  | [
      .[]
      | select(has("pull_request") | not)
      | (.body // "") as $body
      | ($body | contains($marker)) as $marked
      | select($marked or ($body | test($link)))
      | . + {
          match: (if $marked then "marker" else "link" end),
          analyzed: (
            (($body | contains("<!-- analyze-sentry-issue-findings:start -->"))
              and ($body | contains("<!-- analyze-sentry-issue-findings:end -->")))
            or (($marked | not) and ($body | test("(?m)^## Sentry closeout[[:space:]]*$")))
          )
        }
    ]
  | sort_by([(if .state == "open" then 0 else 1 end), (if .match == "marker" then 0 else 1 end), -.number]);
