import click
import os
import shutil
import sys
from os import path


@click.command()
@click.option("--location", help="Location of git repository on file system")
@click.option("--package-file", help="Package file name")
@click.option("--destination", help="Destination")
def main(location, package_file, destination):
    if not package_file:
        package_file = path.join(location, "package.txt")

    if not path.exists(package_file):
        return click.echo("Package file not found at `%s`" % package_file, err=True)
    
    if path.exists(destination):
        shutil.rmtree(destination)
    os.makedirs(destination, exist_ok=True)

    module_locs = []
    with open(package_file, "r") as package_fh:
        lines = package_fh.readlines()
        for line in lines:
            line = line.strip()
            if not line:
                continue
            module_loc = path.join(location, line)
            module_name = line.split("/")[-1]
            if not path.exists(module_loc):
                click.echo("Module not found at `%s`" % module_loc, err=True)
                sys.exit(1)
            module_locs.append(module_loc)
            shutil.copytree(module_loc, path.join(destination, module_name))
    
if __name__ == "__main__":
    main()
