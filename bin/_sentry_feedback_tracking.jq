# The GitHub issues among an array of REST issue objects that track Sentry
# feedback $slug, canonical first: marker before a link to $permalink, then
# newest, open or closed, since each feedback item is one submission. Each
# gains `match` ("marker" or "link") and `analyzed`.
def sentry_feedback_tracking($slug; $permalink):
  ("<!-- sentry-feedback:" + $slug + " -->") as $marker
  | [
      .[]
      | select(has("pull_request") | not)
      | (.body // "") as $body
      | ($body | contains($marker)) as $marked
      | select($marked or ($permalink != "" and ($body | contains($permalink))))
      | . + {
          match: (if $marked then "marker" else "link" end),
          analyzed: (($body | contains("<!-- analyze-sentry-feedback-findings:start -->"))
            and ($body | contains("<!-- analyze-sentry-feedback-findings:end -->")))
        }
    ]
  | sort_by([(if .match == "marker" then 0 else 1 end), -.number]);
