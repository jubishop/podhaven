# Sentry tracking-issue rules that the intake checkers and pickers share. Keep
# them in this one module: jq 1.8.2 aborts when a module passes arguments to a
# function from a module it includes.

# Whether a REST issue or comment object came from the Sentry Intake
# workflow's token, which GraphQL and `gh issue view` name `github-actions`.
def sentry_intake_bot:
  .user.login? == "github-actions[bot]" and .user.type? == "Bot";

# Whether a REST issue object came from the intake bot or the repository's
# $owner. Only they can open tracking issues, since this repository is public
# and anyone can copy a marker or link into an issue.
def sentry_trusted_author($owner):
  sentry_intake_bot
  or (.user.type? == "User"
    and ((.user.login? // "") | ascii_downcase) == ($owner | ascii_downcase));

# The GitHub issues among an array of REST issue objects that track Sentry
# error issue $id, canonical first: open before closed, marker before link,
# then newest. Each gains `match` ("marker" or "link") and `analyzed`.
def sentry_issue_tracking($id; $owner):
  ("<!-- sentry-issue:" + $id + " -->") as $marker
  | ("https?://(artisanal-software[.])?sentry[.]io/(organizations/artisanal-software/)?issues/"
      + $id + "([/?#[:space:]<>)]|$)") as $link
  | [
      .[]
      | select((has("pull_request") | not) and sentry_trusted_author($owner))
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

# The GitHub issues among an array of REST issue objects that track Sentry
# feedback $slug, canonical first: marker before a link to $permalink, then
# newest, open or closed, since each feedback item is one submission. Each
# gains `match` ("marker" or "link") and `analyzed`.
def sentry_feedback_tracking($slug; $permalink; $owner):
  ("<!-- sentry-feedback:" + $slug + " -->") as $marker
  | [
      .[]
      | select((has("pull_request") | not) and sentry_trusted_author($owner))
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
