# Maintenance

## Configuring a new package

This repository expects to receive a `repository_dispatch` event from a GitHub repository that contains the package to be published.

To publish a package, you need to:

1. Add the `RAML_DEV_AUTOMATIONS_APP_CLIENT_ID` and `RAML_DEV_AUTOMATIONS_APP_PRIVATE_KEY` secrets to the GitHub repository that contains the package to be published.

    > [!NOTE]
    >
    > Only raml-dev owners know how to retrieve the private key.

2. Ensure you build and release Windows packages within your GitHub Actions workflow, with the following artifact names:

    - `<package_name>_windows_amd64.deb`
    - `<package_name>_windows_arm64.deb`

3. Dispatch a `repository_dispatch` event to this repository with the following payload:

    ```json
    {
      "event_type": "linux-package-release",
      "client_payload": {
        "release": {
          "version": "${GITHUB_REF_NAME}",
          "api_url": "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/releases/tags/${GITHUB_REF_NAME}",
          "html_url": "${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/releases/tags/${GITHUB_REF_NAME}"
        },
        "package": {
          "name": "${PACKAGE_NAME}",
          "source_repository": "raml-dev/${REPO}",
          "app_name": "App display name",
          "description": "App description",
          "license": "SPDX License",
        }
      }
    }
    ```

You can see an example of this in the [raml-dev/solo](https://github.com/raml-dev/solo) repository.

## Local testing

This project uses [mise](https://mise.jdx.dev) to manage tooling versions and tasks. It's also used in the workflow, which means that you can test the workflow locally using the same mechanisms as the workflow.

To test the workflow locally:

- Copy `mise.local.toml.example` to `mise.local.toml`
- Populate all variables in `mise.local.toml` with the appropriate values
- Run:

    ```bash
    mise install
    mise run local-publish-test
    ```
