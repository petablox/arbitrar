from typing import List, Optional
import subprocess
import traceback
import glob
import shutil
import os
import magic

from src.database import Database, Pkg, PkgSrcType, Build, BuildType, BuildResult


def exists(path: str, files: List[str]) -> Optional[str]:
  for f in files:
    if os.path.exists(os.path.join(path, f)):
      return f
  return None


def find_build(db: Database, pkg: Pkg):
  src_dir = db.package_source_dir(pkg)
  if pkg.pkg_src.src_type == PkgSrcType.debian:
    pkg.build = Build(BuildType.dpkg)
  elif exists(src_dir, ["configure", "config"]) is not None:
    pkg.build = Build(BuildType.config)
  elif exists(src_dir, ["Makefile", "makefile"]) is not None:
    pkg.build = Build(BuildType.makeonly)
  else:
    pkg.build = Build(BuildType.unknown)


class BuildException(Exception):
  pass


class BuildEnv:
  def __init__(self):
    self.env = os.environ.copy()
    self.env["LLVM_COMPILER"] = "clang"
    self.env["CC"] = "wllvm"
    self.env["CXX"] = "wllvm++"
    self.env["CFLAGS"] = "-g -O1"
    self.env["DEB_CFLAGS_SET"] = "-g -O1"
    self.env["DEB_BUILD_OPTIONS"] = "nocheck notest"


def get_soname(path):
  objdump = subprocess.Popen(['objdump', '-p', path], stdout=subprocess.PIPE)
  out = subprocess.run(['grep', 'SONAME'], stdout=subprocess.PIPE, stdin=objdump.stdout)
  if len(out.stdout) == 0:
    return None
  return out.stdout.strip().split()[-1].decode()


def soname_lib(libpath):
  soname = get_soname(libpath)
  if soname is None:
    soname = libpath.split("/")[-1]
  return soname


def run_make(db: Database, pkg: Pkg):
  src_dir = db.package_source_dir(pkg)

  # Try a re-fetch and clean build with make
  print("building {} with configure/make".format(pkg.name))

  env = BuildEnv()

  if pkg.build.build_type == BuildType.config:

    # TODO: Incorporate this into BuildTypes enum
    config_file = exists(src_dir, ["configure", "config"])
    if config_file is None:
      raise BuildException("should never happen")

    run = subprocess.run(["./" + config_file],
                         stdout=subprocess.DEVNULL,
                         stderr=subprocess.STDOUT,
                         cwd=src_dir,
                         env=env.env)

    if run.returncode != 0:
      raise BuildException("configure failed")

  run = subprocess.run(['make', '-j32'], stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT, cwd=src_dir, env=env.env)

  if run.returncode != 0:
    raise BuildException("make failed")


def run_dpkg(db: Database, pkg: Pkg):
  src_dir = db.package_source_dir(pkg)

  env = BuildEnv()

  run = subprocess.run(['dpkg-buildpackage', '-us', '-uc', '-d'], stderr=subprocess.STDOUT, cwd=src_dir, env=env.env)
  if run.returncode != 0:
    raise BuildException("dpkg-buildpakcage failed")


# Really, this can only work for debian packages, but perhaps in the future we can support
# more build systems, so I'm seperating out the step from the main build
def build_dep(db: Database, pkg: Pkg):
  if pkg.build.build_type != BuildType.dpkg:
    return

  run = subprocess.run(['sudo', 'apt-get', 'build-dep', '-y', pkg.pkg_src.link], stderr=subprocess.STDOUT)
  if run.returncode != 0:
    raise BuildException("dependency build failed")


def build_pkg(db: Database, pkg: Pkg):
  if pkg.build.build_type == BuildType.config or pkg.build.build_type == BuildType.makeonly:
    run_make(db, pkg)
  elif pkg.build.build_type == BuildType.dpkg:
    run_dpkg(db, pkg)
  else:
    raise BuildException("not yet implemented")
  pkg.build.result = BuildResult.compiled


# I am unsure how your analysis needs to be structured, so I will keep the extract-bc intact
# as is, but this process essentially grabs the debian packaged libs and puts them into the
# source folder
def install_libs(db: Database, pkg: Pkg):
  if pkg.build.build_type != BuildType.dpkg:
    return None

  pkg_dir = db.package_dir(pkg)

  debs = glob.glob(f"{pkg_dir}/*.deb")
  req_deb = ""

  for d in debs:
    if f"{pkg.pkg_src.link}_" in d:
      req_deb = d
      break

  if req_deb == "":
    raise BuildException("could not find requested debian package after build")

  run = subprocess.run(['dpkg', '-x', req_deb, pkg_dir], stdout=subprocess.PIPE)
  if run.returncode != 0:
    raise BuildException("could not extract debian package")

  ulibs = find_libs(f"{pkg_dir}/usr")
  llibs = find_libs(f"{pkg_dir}/lib")
  libs = ulibs + llibs

  new_libs = []
  for l in libs:
    name = l.split("/")[-1]
    shutil.copy(l, f"{pkg_dir}/source")
    new_libs.append(("lib", f"{pkg_dir}/source/{name}"))

  # Going to also look for some ndirs = ["bin", "sbin", "usr/bin", "usr/sbin"]

  bindirs = ["bin", "sbin", "usr/bin", "usr/sbin"]
  binaries = []

  for b in bindirs:
    for (dirpath, dirnames, filenames) in os.walk(f"{pkg_dir}/{b}"):
      for f in filenames:
        p = os.path.join(dirpath, f)
        mime = magic.from_file(p, mime=True)
        is_exec = mime == 'application/x-executable'
        is_shlib = mime == 'application/x-sharedlib'
        if not os.path.islink(p) and (is_exec or is_shlib):
          binaries.append(p)

  for b in binaries:
    name = b.split("/")[-1]
    shutil.copy(b, f"{pkg_dir}/source")
    new_libs.append(("bin", f"{name}"))

  return new_libs


def find_libs(path: str) -> List[str]:
  out = subprocess.run(['find', path, '-name', 'lib*.so*'], stdout=subprocess.PIPE)
  libs = []
  for l in out.stdout.splitlines():
    libs.append(l.decode('utf-8'))
  return libs


def extract_bc(db: Database, pkg: Pkg, libs=None):
  src_dir = db.package_source_dir(pkg)

  if libs is None:
    libs = find_libs(src_dir)
    libs = list(map(lambda x: ("lib", x), libs))

  if len(libs) == 0:
    pkg.build.result = BuildResult.nolibs
    raise BuildException("nolibs")

  extracts = set()
  for l in libs:
    t, n = l
    if t == "lib":
      extracts.add(get_soname(n))
    else:
      extracts.add(n)

  if len(extracts) == 0:
    pkg.build.result = BuildResult.nolibs
    raise BuildException("nolibs")
  pkg.build.libs = list(extracts)

  for l in pkg.build.libs:
    if not os.path.exists(f"{src_dir}/{l}.bc"):
      run = subprocess.run(["extract-bc", l], stderr=subprocess.STDOUT, cwd=src_dir)
      if run.returncode != 0:
        pkg.build.result = BuildResult.nobc
        raise BuildException("nobc")

  pkg.build.result = BuildResult.success


def compile_pkg(db: Database, pkg: Pkg):
  try:
    find_build(db, pkg)
    build_dep(db, pkg)
    build_pkg(db, pkg)
    libs = install_libs(db, pkg)
    extract_bc(db, pkg, libs)
  except BuildException as e:
    print(e)
    traceback.print_exc()
