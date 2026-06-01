project('singularity-calendar', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.59.0'
)

i18n = import('i18n')
add_project_arguments('-DGETTEXT_PACKAGE="singularity-calendar"', language: 'c')
subdir('po')

gnome = import('gnome')

add_project_arguments('-DGOA_API_IS_SUBJECT_TO_CHANGE', language: 'c')

gtk_dep  = dependency('gtk4')
gee_dep  = dependency('gee-0.8')
goa_dep  = dependency('goa-1.0')
soup_dep = dependency('libsoup-3.0')

libsingularity_dep = dependency('singularity-1.0',
  fallback: ['libsingularity', 'libsingularity_dep']
)

if not meson.is_subproject() and libsingularity_dep.type_name() == 'internal'
  libsingularity_vapi_dir = join_paths(meson.project_build_root(), 'subprojects', 'libsingularity')
  add_project_arguments(['--vapidir=' + libsingularity_vapi_dir], language: 'vala')
endif

subdir('ui')

resources = gnome.compile_resources(
  'singularity-calendar-resources',
  'resources/dev.sinty.calendar.gresource.xml',
  source_dir: [meson.current_source_dir(), meson.current_build_dir()],
  dependencies: main_ui
)

sources = files(
  'src/main.vala',
  'src/window.vala',
  'src/app.vala',
  'src/local_provider.vala',
  'src/goa_provider.vala',
)

executable('singularity-calendar',
  sources + [resources],
  dependencies: [gtk_dep, gee_dep, goa_dep, soup_dep, libsingularity_dep],
  install: true
)

install_data('data/dev.sinty.calendar.desktop',
  install_dir: get_option('datadir') / 'applications'
)

install_data('data/dev.sinty.calendar.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)

install_data('data/dev.sinty.calendar.json',
  install_dir: get_option('datadir') / 'singularity' / 'apps'
)

install_data('data/icons/dev.sinty.calendar.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)
