# Speed

A minimal macOS task management app with a unique "Speed Mode" feature for focused task completion.

## Creating Releases

Speed uses GitHub Actions for automated releases and Sparkle for auto-updates. Here's how to create a new release:

### Quick Release (Recommended)

1. Ensure all your changes are committed and pushed
2. Run the version bump script:

   ```bash
   # For patch version (1.0.0 -> 1.0.1):
   ./bump_version.sh

   # For minor version (1.0.0 -> 1.1.0):
   ./bump_version.sh -m

   # For major version (1.0.0 -> 2.0.0):
   ./bump_version.sh -M

   # For specific version:
   ./bump_version.sh -v 1.2.3
   ```

3. Review the changes
4. Commit and push:
   ```bash
   git add .
   git commit -m "Bump version to X.Y.Z"
   git push
   ```
5. Create and push the tag:
   ```bash
   git tag vX.Y.Z
   git push --tags
   ```
6. GitHub Actions will automatically:
   - Build the app
   - Create a GitHub release
   - Upload the app bundle
   - Update the appcast.xml with the correct signature

### Manual Release (Advanced)

If you need more control over the release process:

1. Update version numbers:

   - In `create_release.sh`: Update `VERSION="X.Y.Z"`
   - In Xcode project settings: Update version number
   - In `project.pbxproj`: Update `MARKETING_VERSION`

2. Update `appcast.xml`:

   - Add new version entry at the top
   - Update version numbers
   - Update release notes
   - Update download URL
   - Leave `sparkle:edSignature` as "SIGNATURE_PLACEHOLDER"

3. Commit changes:

   ```bash
   git add .
   git commit -m "Prepare for version X.Y.Z release"
   git push
   ```

4. Create and push tag:

   ```bash
   git tag vX.Y.Z
   git push --tags
   ```

5. Wait for GitHub Actions to complete the release

### Troubleshooting

If something goes wrong:

1. Delete the tag:

   ```bash
   git tag -d vX.Y.Z
   git push --delete origin vX.Y.Z
   ```

2. Delete the GitHub release if it was created

3. Fix any issues

4. Start the release process again

### Version Numbers

- **Patch version** (1.0.0 -> 1.0.1): Bug fixes and minor improvements
- **Minor version** (1.0.0 -> 1.1.0): New features, backward compatible
- **Major version** (1.0.0 -> 2.0.0): Breaking changes or significant updates

### Release Checklist

Before creating a release:

- [ ] All changes are committed and pushed
- [ ] Tests pass
- [ ] Documentation is updated
- [ ] Release notes are prepared
- [ ] Version numbers are consistent across all files
- [ ] Previous version can successfully auto-update to this version
