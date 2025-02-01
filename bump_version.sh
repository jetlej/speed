#!/bin/bash

# Function to increment version
increment_version() {
    local version=$1
    local position=${2:-2}  # Default to patch position (1.0.0 -> 1.0.1)
    
    # Split version into array
    IFS='.' read -ra ver_parts <<< "$version"
    
    # Pad with zeros if needed
    while [ ${#ver_parts[@]} -lt 3 ]; do
        ver_parts+=("0")
    done
    
    # Increment the specified position
    ver_parts[$position]=$((ver_parts[$position] + 1))
    
    # Reset all positions after the incremented one
    for (( i=position+1; i<${#ver_parts[@]}; i++ )); do
        ver_parts[$i]=0
    done
    
    # Join back with dots
    echo "${ver_parts[*]}" | tr ' ' '.'
}

# Function to get current version from appcast.xml
get_current_version() {
    grep -m 1 '<sparkle:version>' appcast.xml | sed 's/.*<sparkle:version>\(.*\)<\/sparkle:version>.*/\1/'
}

# Function to update version in create_release.sh
update_release_script() {
    local new_version=$1
    sed -i '' "s/VERSION=\".*\"/VERSION=\"$new_version\"/" create_release.sh
}

# Function to update version in project.pbxproj
update_project_version() {
    local new_version=$1
    sed -i '' "s/MARKETING_VERSION = .*;/MARKETING_VERSION = $new_version;/" Speed.xcodeproj/project.pbxproj
}

# Function to add new version to appcast.xml
update_appcast() {
    local new_version=$1
    local date=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")
    local template="        <item>\n            <title>Version $new_version</title>\n            <pubDate>$date</pubDate>\n            <sparkle:version>$new_version</sparkle:version>\n            <sparkle:shortVersionString>$new_version</sparkle:shortVersionString>\n            <description><![CDATA[\n                <h2>Version $new_version</h2>\n                <ul>\n                    <li>Updates and improvements</li>\n                </ul>\n            ]]></description>\n            <link>https://github.com/jetlej/Speed/releases/tag/v$new_version</link>\n            <enclosure\n                url=\"https://github.com/jetlej/Speed/releases/download/v$new_version/Speed.app.zip\"\n                sparkle:version=\"$new_version\"\n                sparkle:shortVersionString=\"$new_version\"\n                length=\"0\"\n                type=\"application/octet-stream\"\n                sparkle:edSignature=\"SIGNATURE_PLACEHOLDER\"\n            />\n        </item>"
    
    # Insert new version entry after <title>Speed Updates</title>
    sed -i '' "/<title>Speed Updates<\/title>/a\\
$template
" appcast.xml
}

# Main script
current_version=$(get_current_version)
echo "Current version: $current_version"

# Parse arguments
position=2  # Default to patch increment
new_version=""

while getopts "v:Mmp" opt; do
    case $opt in
        v) new_version="$OPTARG";;
        M) position=0;;  # Major version
        m) position=1;;  # Minor version
        p) position=2;;  # Patch version
        \?) echo "Invalid option: -$OPTARG" >&2; exit 1;;
    esac
done

# If no version specified, increment current version
if [ -z "$new_version" ]; then
    new_version=$(increment_version "$current_version" "$position")
fi

echo "Bumping to version: $new_version"

# Update all version references
update_release_script "$new_version"
update_project_version "$new_version"
update_appcast "$new_version"

echo "Version bump complete! Changes made:"
echo "- Updated create_release.sh"
echo "- Updated project.pbxproj"
echo "- Added new version to appcast.xml"
echo ""
echo "Next steps:"
echo "1. Review the changes"
echo "2. Commit the changes: git add . && git commit -m \"Bump version to $new_version\""
echo "3. Create and push the tag: git tag v$new_version && git push && git push --tags" 