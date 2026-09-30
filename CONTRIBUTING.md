# Contributing

Work is tracked in [Jira (project KAN)](https://lpnu-team-qggd0gqk.atlassian.net/jira/software/projects/KAN/boards/2). Put the ticket key in your branch, commits, and PR title so the work shows up on the Jira ticket and `KAN-123` links back to Jira from GitHub.

## Workflow

1. Pick a ticket in Jira and move it to *In Progress*.
2. Create a branch that starts with the key:

   ```sh
   git switch -c KAN-123-short-description
   ```

   Jira's **Create branch** button on a ticket suggests this name for you.
3. Commit with the key at the start of the message:

   ```
   KAN-123 Add due date picker to task form
   ```

4. Open a PR titled `KAN-123: Short description`. `main` only accepts squash merges, so the PR title becomes the commit on `main`.
5. Resolve all review threads, then merge. The branch is deleted automatically.

## Smart commits (optional)

With the Jira GitHub integration connected, commit messages can act on the ticket. Your Git commit email must match your Jira account email.

```
KAN-123 #comment Fixed the overflow on mobile
KAN-123 #time 1h 30m
KAN-123 #done
```

`#done` (or any other transition name, e.g. `#in-review`) must match a transition in the KAN workflow.
