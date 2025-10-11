import json
import re
import subprocess
import sys
from pathlib import Path


service_name_map = {
    'pixiv': 'pixiv',
    'nijie.info': 'nijie',
    'patreon': 'patreon',
    'newgrounds': 'newgrounds',
    'mastodon instances': 'mastodon',
    'misskey instances': 'misskey',
    'webtoons': 'webtoons',
    'danbooru': 'danbooru',
    'aibooru': 'aibooru',
    'atfbooru': 'atfbooru',
    'gelbooru': 'gelbooru',
    'sankaku': 'sankaku',
    'sankaku idolcomplex': 'sankakuIdolcomplex',
    'hentaifoundry': 'hentaiFoundry',
    'deviantart': 'deviantArt',
    'twitter': 'twitter',
    'bluesky': 'bluesky',
    'kemono.party': 'kemonoParty',
    'coomer.party': 'coomerParty',
    '3dbooru': '_3dbooru',
    'safebooru': 'safebooru',
    'tumblr': 'tumblr',
    'fantia': 'fantia',
    'fanbox': 'fanbox',
    'lolibooru': 'lolibooru',
    'yande.re': 'yandere',
    'artstation': 'artstation',
    'imgur': 'imgur',
    'seiso.party': 'seisoParty',
    'rule34.xxx': 'rule34xxx',
    'e621': 'e621',
    'furaffinity': 'furaffinity',
    'instagram': 'instagram',
    'redgifs': 'redgifs',
    'tiktok': 'tiktok',
    'reddit': 'reddit',
    'iwara': 'iwara'
}


def run_command(cmd):
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"Error running command: {cmd}", file=sys.stderr)
        print(f"Error output: {e.stderr}", file=sys.stderr)
        raise


def get_input_file_path():
    return Path(run_command(
      """
      nix build --no-link --print-out-paths \
        --extra-experimental-features nix-command \
        --extra-experimental-features flakes \
        .#hydownloader.src
      """
    )) / "hydownloader" / "data" / "hydownloader-import-jobs.py"


def get_source_hash():
    return run_command(
      """
      nix eval \
        --extra-experimental-features nix-command \
        --extra-experimental-features flakes \
        .#hydownloader.src.outputHash
      """
    ).strip('"')


def parse_sections(file_path):
    with open(file_path, 'r') as f:
        lines = f.readlines()
    sections = []
    current_section = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if (
          line.strip() == '#' and
          i + 1 < len(lines) and
          lines[i + 1].startswith('#')
        ):
            if current_section:
                sections.append(''.join(current_section))
                current_section = []
            comment_block = [line]
            i += 1
            while i < len(lines) and lines[i].startswith('#'):
                comment_block.append(lines[i])
                i += 1
            if i < len(lines) and lines[i].strip() == '#':
                comment_block.append(lines[i])
                i += 1
            current_section = comment_block
            continue
        current_section.append(line)
        i += 1
    if current_section:
        sections.append(''.join(current_section))
    return sections


def identify_section(section_text):
    lines = section_text.strip().split('\n')
    for line in lines[:10]:
        if '# Some common values used in the default import job' in line:
            return 'commonConfig'
        elif '# Default import job - main config' in line:
            return 'defaultImportJob'
        elif '# Default import job - generic tag/URL rules' in line:
            return 'defaultRules'
        elif line.startswith('# Rules for '):
            match = re.match(r'# Rules for (.+)$', line)
            if match:
                service_name = match.group(1).strip().lower()
                return ('rules', service_name)
    return 'unknown'


def main():
    input_file = get_input_file_path()
    if not input_file.exists():
        print(f"Error: File {input_file} not found", file=sys.stderr)
        return 1
    source_hash = get_source_hash()
    sections = parse_sections(input_file)
    output = {}
    output['sourceHash'] = source_hash
    rules_sections = {}
    for section in sections:
        section_type = identify_section(section)
        if section_type == 'commonConfig':
            output['commonConfig'] = section
        elif section_type == 'defaultImportJob':
            output['defaultImportJob'] = section
        elif section_type == 'defaultRules':
            output['defaultRules'] = section
        elif isinstance(section_type, tuple) and section_type[0] == 'rules':
            service_name = section_type[1]
            if service_name in service_name_map:
                mapped_name = service_name_map[service_name]
                rules_sections[mapped_name] = section
            else:
                print(
                  f"Error: Unknown service name '{service_name}'",
                  file=sys.stderr,
                )
                return 1
        elif section_type == 'unknown':
            print("Error: Found unknown section", file=sys.stderr)
            print(f"Section preview: {section[:200]}...", file=sys.stderr)
            return 1
    if rules_sections:
        output['rules'] = rules_sections
    output_file = Path('overlay/packages/hydownloader/importJob.json')
    with open(output_file, 'w') as f:
        json.dump(output, f, indent=2)
    return 0


if __name__ == '__main__':
    sys.exit(main())
