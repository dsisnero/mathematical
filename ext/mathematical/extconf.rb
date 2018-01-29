ENV['RC_ARCHS'] = '' if RUBY_PLATFORM =~ /darwin|mac os/

require 'mkmf'
require 'rbconfig'
require 'pry'
require 'pathname'

OS         = case RbConfig::CONFIG['host_os']
             when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
               :windows
             when /darwin|mac os/
               :macos
             when /linux/
               :linux
             when /solaris|bsd/
               :unix
             else
               raise Error::WebDriverError, "unknown os: #{host_os.inspect}"
             end

LIBDIR     = RbConfig::CONFIG['libdir']
INCLUDEDIR = RbConfig::CONFIG['includedir']
SHARED_EXT = OS == :macos ? 'dylib' : 'so'

HEADER_DIRS = [

  INCLUDEDIR
]

LIB_DIRS = [LIBDIR]


unless find_executable('cmake')
  $stderr.puts "\n\n\n[ERROR]: cmake is required and not installed. Get it here: http://www.cmake.org/\n\n"
  exit 1
end

def using_system_lasem?
  arg_config('--use-system-lasem', !!ENV['MATHEMATICAL_USE_SYSTEM_LASEM'])
end

def using_system_mtex2mml?
  arg_config('--use-system-mtex2MML', !!ENV['MATHEMATICAL_USE_SYSTEM_MTEX2MML'])
end

ROOT_TMP = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'tmp'))

EXTCONF_DIR = Pathname(__dir__)
root2 = EXTCONF_DIR.parent.parent + 'tmp'





LASEM_DIR = EXTCONF_DIR + 'lasem'

LASEM_BUILD_DIR = LASEM_DIR + 'build'

LASEM_SRC_DIR = LASEM_DIR + 'src'

LASEM_LIB_DIR = EXTCONF_DIR + 'lib'


MTEX2MML_DIR  = EXTCONF_DIR + 'mtext2MML'

MTEX2MML_BUILD_DIR = MTEX2MML_DIR + 'build'

MTEX2MML_SRC_DIR = MTEX2MML_DIR + 'src'

MTEX2MML_LIB_DIR = EXTCONF_DIR + 'lib'

if OS == :macos
  ENV['PKG_CONFIG_PATH'] = "/opt/X11/lib/pkgconfig:#{ENV['PKG_CONFIG_PATH']}"
end


# pre-compile checks
have_library('xml2')
have_library('pangocairo-1.0')

libxml_include_dirs = ['/include/libxml2', '/usr/include/libxml2', '/usr/local/include/libxml2']

if lib_xml_dir = pkg_config('libxml-2.0', 'cflags-only-I')
  libxml_include_dirs.unshift lib_xml_dir[/-I(.+)/,1]
end

find_header('libxml/tree.h', *libxml_include_dirs)
find_header('libxml/parser.h', *libxml_include_dirs)
find_header('libxml/xpath.h', *libxml_include_dirs)
find_header('libxml/xpathInternals.h', *libxml_include_dirs)

# TODO: we need to clear out the build dir that's erroneously getting packaged
# this causes problems, as Linux installation is expecting OS X output
def clean_dir(dir)
  if File.directory?(dir) && !File.exist?(ROOT_TMP)
    FileUtils.rm_rf(dir)
  end
  FileUtils.mkdir_p(dir)
end

clean_dir(MTEX2MML_BUILD_DIR)
clean_dir(LASEM_BUILD_DIR)

if !using_system_mtex2mml?
  # build mtex2MML library
  Dir.chdir(MTEX2MML_BUILD_DIR) do
    system 'cmake ..'
    system 'make libmtex2MML_static'
  end
  FileUtils.mkdir_p(MTEX2MML_LIB_DIR)
  FileUtils.cp_r(File.join(MTEX2MML_BUILD_DIR, 'libmtex2MML.a'), MTEX2MML_LIB_DIR)
  $LIBS << ' -lmtex2MML'
  LIB_DIRS << MTEX2MML_LIB_DIR
  HEADER_DIRS << MTEX2MML_SRC_DIR
else
  if dir_config('mtex2MML').any? || system('dpkg -s libmtex2MML >/dev/null')
    $LIBS << ' -lmtex2MML'
  else
    # NOTE: pkg_config implicitly adds right -l argument for the linker.
    pkg_config('libmtex2MML') || pkg_config('mtex2MML')
  end
end

if !using_system_lasem?
  # build Lasem library
  # SHOULD BE DYNAMICALLY LINKED for potential LGPL copyright issues
  Dir.chdir(LASEM_BUILD_DIR) do
    system 'cmake ../..'
    system 'make'
  end
  FileUtils.mkdir_p(LASEM_LIB_DIR)
  FileUtils.cp_r(File.join(LASEM_BUILD_DIR, "liblasem.#{SHARED_EXT}"), LASEM_LIB_DIR)
  if OS == :linux
    $LIBS << " -Wl,-rpath,#{LASEM_LIB_DIR} -llasem"
  else
    $LIBS << ' -llasem'
  end
  LIB_DIRS << LASEM_LIB_DIR
  HEADER_DIRS << LASEM_SRC_DIR
else
  if dir_config('lasem').any? || system('dpkg -s liblasem >/dev/null')
    $LIBS << ' -llasem'
  else
    # NOTE: pkg_config implicitly adds right -l argument for the linker.
    pkg_config('liblasem') || pkg_config('lasem') || pkg_config('lasem-0.4')
  end
end

if !using_system_mtex2mml?
LIB_DIRS = [MTEX2MML_LIB_DIR, LASEM_LIB_DIR]
HEADER_DIRS = [MTEX2MML_SRC_DIR, LASEM_SRC_DIR]

dir_config('mathematical', HEADER_DIRS, LIB_DIRS)

find_header('mtex2MML.h', MTEX2MML_SRC_DIR)
end

flag = ENV['TRAVIS'] ? '-O0' : '-O2'
$LDFLAGS << " #{`pkg-config --static --libs glib-2.0 gdk-pixbuf-2.0 cairo pango`.chomp}"
$CFLAGS << " #{flag} #{`pkg-config --cflags glib-2.0 gdk-pixbuf-2.0 cairo pango`.chomp}"

create_makefile('mathematical/mathematical')
