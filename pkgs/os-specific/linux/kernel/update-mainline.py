#!/usr/bin/env python3
import html.parser
import json
import pathlib
import re
import subprocess
import urllib.request


HERE = pathlib.Path(__file__).parent
ROOT = HERE.parent.parent.parent.parent
VERSIONS_FILE = HERE / "mainline-kernels.json"


class LinksParser(html.parser.HTMLParser):
    def __init__(self, *, convert_charrefs: bool = True) -> None:
        super().__init__(convert_charrefs=convert_charrefs)
        self.kernels = {}

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attrs_ = dict(attrs)
        if tag == "a" and attrs_.get("title") == "Download complete tarball":
            url = attrs_["href"]
            assert url

            if "-rc" in url:
                return

            version = re.search("linux-(.*).tar.xz", url)
            assert version

            self.kernels[version.group(1)] = url


def get_branch(version: str):
    major, minor, *_ = version.split(".")
    return f"{major}.{minor}"


def get_hash(url: str):
    return subprocess.check_output(["nix-prefetch-url", url]).decode().strip()


def commit(message):
    return subprocess.check_call(["git", "commit", "-m", message, VERSIONS_FILE])


def main():
    kernel_org = urllib.request.urlopen("https://kernel.org/")
    parser = LinksParser()
    parser.feed(kernel_org.read().decode())

    all_kernels = json.load(VERSIONS_FILE.open())

    for version, link in parser.kernels.items():
        branch = get_branch(version)

        old_version = all_kernels.get(branch, {}).get("version")
        if old_version == version:
            print(f"linux-{branch}: {version} is latest, skipping...")
            continue

        if old_version is None:
            message = f"linux-{branch}: init at {version}"
        else:
            message = f"linux-{branch}: {old_version} -> {version}"

        print(message)

        all_kernels[branch] = {"version": version, "hash": get_hash(link)}

        with VERSIONS_FILE.open("w") as fd:
            json.dump(all_kernels, fd, indent=4)
            fd.write("\n")  # makes editorconfig happy

        commit(message)


if __name__ == "__main__":
    main()
