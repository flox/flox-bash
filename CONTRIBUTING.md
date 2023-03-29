# Flox CLI and Library

The [flox](https://floxdev.com) CLI is a multi-platform environment manager built on [Nix](https://github.com/nixOS/nix).


### CLA

- [ ] All commits in a Pull Request are [signed](https://docs.github.com/en/authentication/managing-commit-signature-verification/signing-commits) and Verified by Github or via GPG.
- [ ] As an outside contributor you need to accept the flox [Contributor License Agreement](.github/CLA.md) by adding your Git/Github details in a row at the end of the [`CONTRIBUTORS.csv`](.github/CONTRIBUTORS.csv) file by way of the same pull request or one done previously.

### Commits

This project follows (tries to),
[conventional commits](https://www.conventionalcommits.org/en/v1.0.0/).

We employ [commitizen](https://commitizen-tools.github.io/commitizen/)
to help enforcing those rules.

**Commit messages that explain the content of the commit are appreciated**

-----

For starters: commit messages shold have to follow the pattern:

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

The commit contains the following structural elements,
to communicate intent to the consumers of your library:

1. **fix**: a commit of the type `fix` patches a bug in your codebase
   (this correlates with PATCH in Semantic Versioning).
2. **feat**: a commit of the type feat introduces a new feature to the codebase
   (this correlates with MINOR in Semantic Versioning).
3. **BREAKING CHANGE**: a commit that has a footer BREAKING CHANGE:,
   or appends a ! after the type/scope, introduces a breaking API change
   (correlating with MAJOR in Semantic Versioning).
   A BREAKING CHANGE can be part of commits of any type.
4. types other than fix: and feat: are allowed,
   for example @commitlint/config-conventional (based on the Angular convention)
   recommends `build`, `chore`, `ci`, `docs`, `style`, `refactor`, `perf`,
   `test`, and others.
5. footers other than BREAKING CHANGE: <description> may be provided
   and follow a convention similar to git trailer format.

Additional types are not mandated by the Conventional Commits specification,
and have no implicit effect in Semantic Versioning
(unless they include a BREAKING CHANGE).

A scope may be provided to a commit’s type,
to provide additional contextual information
and is contained within parenthesis, e.g., feat(parser): add ability to parse
arrays.

-----

A pre-commit hook will ensure only corrextly formatted commit messages are
committed.

You can also run

```
$ cz c
```

or

```
$ cz commit
```

to make conforming commits interactively.

### Merges

This repo follows a variant of [git-flow](https://www.atlassian.com/git/tutorials/comparing-workflows/gitflow-workflow).

Features are branched off the `develop` branch and committed back to it,
upon completion, using GitHub PRs.
Features should be **squashed and merged** into `develop`,
or if they represent multiple bigger changes,
squashed into multiple distinct change sets.
