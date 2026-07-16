import { Store, runStoreExtension } from "@vehla/store-sdk";

function inputFor(invocation) {
  return (
    invocation.query ||
    invocation.context.selectedText ||
    invocation.context.clipboardText ||
    ""
  ).trim();
}

function requireInput(invocation, example) {
  const input = inputFor(invocation);
  if (!input) throw new Error(`Input required. Example: ${example}`);
  return input;
}

function parts(value) {
  return value.split("|").map((part) => part.trim());
}

function repositoryFrom(value) {
  const cleaned = value
    .trim()
    .replace(/^https?:\/\/github\.com\//i, "")
    .replace(/\.git$/i, "")
    .replace(/\/(?:issues|pull|compare).*$/i, "")
    .replace(/^\/+|\/+$/g, "");
  const match = cleaned.match(/^([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+)$/);
  if (!match) {
    throw new Error("Use owner/repository or a GitHub repository URL.");
  }
  return `${match[1]}/${match[2]}`;
}

function githubURL(path, query = {}) {
  const url = new URL(path, "https://github.com");
  for (const [name, value] of Object.entries(query)) {
    if (value) url.searchParams.set(name, value);
  }
  return url.toString();
}

async function repositorySummary(repository, githubToken) {
  const headers = {
    Accept: "application/vnd.github+json",
    "User-Agent": "Vehla-Store-GitHub-Workflow",
    "X-GitHub-Api-Version": "2022-11-28",
  };
  if (githubToken) headers.Authorization = `Bearer ${githubToken}`;

  const response = await fetch(`https://api.github.com/repos/${repository}`, {
    headers,
  });
  if (!response.ok) {
    const remaining = response.headers.get("x-ratelimit-remaining");
    throw new Error(
      `GitHub returned ${response.status} ${response.statusText}` +
        (remaining === "0" ? ". The public API rate limit has been reached." : "."),
    );
  }
  const repo = await response.json();
  return [
    `# ${repo.full_name}`,
    "",
    repo.description || "No description.",
    "",
    `- Stars: ${repo.stargazers_count.toLocaleString()}`,
    `- Forks: ${repo.forks_count.toLocaleString()}`,
    `- Open issues: ${repo.open_issues_count.toLocaleString()}`,
    `- Primary language: ${repo.language || "Not specified"}`,
    `- Default branch: ${repo.default_branch}`,
    `- License: ${repo.license?.spdx_id || "Not specified"}`,
    `- Visibility: ${repo.visibility}`,
    `- Last pushed: ${repo.pushed_at}`,
    `- URL: ${repo.html_url}`,
  ].join("\n");
}

runStoreExtension(async (invocation) => {
  switch (invocation.commandID) {
    case "search": {
      const input = requireInput(invocation, "ghsearch repositories | swift");
      const [possibleType, ...rest] = parts(input);
      const typeMap = {
        repositories: "repositories",
        repos: "repositories",
        code: "code",
        issues: "issues",
        users: "users",
      };
      const type = typeMap[possibleType.toLowerCase()];
      const query = type ? rest.join(" | ") : input;
      if (!query) throw new Error("Enter something to search for.");
      return Store.openURL(githubURL("/search", { q: query, type: type || "repositories" }));
    }

    case "open-repository": {
      const repository = repositoryFrom(requireInput(invocation, "ghrepo apple/swift"));
      return Store.openURL(githubURL(`/${repository}`));
    }

    case "repository-summary": {
      const repository = repositoryFrom(requireInput(invocation, "ghsummary apple/swift"));
      return Store.copyText(
        await repositorySummary(repository, invocation.context.secrets?.githubToken),
      );
    }

    case "create-issue": {
      const [rawRepository, title, ...bodyParts] = parts(
        requireInput(invocation, "ghissue owner/repo | Bug title | What happened"),
      );
      const repository = repositoryFrom(rawRepository);
      if (!title) throw new Error("Include an issue title after the first | separator.");
      return Store.openURL(
        githubURL(`/${repository}/issues/new`, {
          title,
          body: bodyParts.join(" | "),
        }),
      );
    }

    case "open-pull-request": {
      const [rawRepository, number] = parts(requireInput(invocation, "ghpr owner/repo | 42"));
      const repository = repositoryFrom(rawRepository);
      if (!/^\d+$/.test(number || "")) throw new Error("Include a numeric pull request number.");
      return Store.openURL(githubURL(`/${repository}/pull/${number}`));
    }

    case "compare-branches": {
      const [rawRepository, base, head] = parts(
        requireInput(invocation, "ghcompare owner/repo | main | feature"),
      );
      const repository = repositoryFrom(rawRepository);
      if (!base || !head) throw new Error("Include both base and head branches.");
      return Store.openURL(githubURL(`/${repository}/compare/${base}...${head}`));
    }

    case "open-profile": {
      const username = requireInput(invocation, "ghuser octocat").replace(/^@/, "");
      if (!/^[A-Za-z0-9-]+$/.test(username)) throw new Error("Enter a valid GitHub username.");
      return Store.openURL(githubURL(`/${username}`));
    }

    default:
      throw new Error(`Unknown command: ${invocation.commandID}`);
  }
});
