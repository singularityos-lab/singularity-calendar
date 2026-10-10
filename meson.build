project('singularity-calendar', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.59.0'
)

i18n = import('i18n')
add_project_arguments('-DGETTEXT_PACKAGE="singularity-calendar"', language: 'c')
subdir('po')

gnome = import('gnome')

gtk_dep  = dependency('gtk4')
gee_dep  = dependency('gee-0.8')
soup_dep = dependency('libsoup-3.0')
json_dep = dependency('json-glib-1.0')

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
  'src/calendar_bus.vala',
  'src/app.vala',
  'src/event_store.vala',
  'src/recurrence_editor.vala',
  'src/event_editor.vala',
  'src/event_details.vala',
  'src/invitations.vala',
  'src/search.vala',
)

executable('singularity-calendar',
  sources + [resources],
  dependencies: [gtk_dep, gee_dep, soup_dep, json_dep, libsingularity_dep],
  install: true
)

shared_module('singularity-calendar-widget',
  files('widget/upcoming_widget.vala'),
  dependencies: [gtk_dep, gee_dep, soup_dep, json_dep, libsingularity_dep],
  install: true,
  install_dir: get_option('libdir') / 'singularity' / 'widgets'
)
install_data('widget/dev.sinty.calendar.upcoming.widget',
  install_dir: get_option('datadir') / 'singularity' / 'widgets'
)

install_data('data/capabilities/dev.sinty.Calendar1.ini',
  install_dir: get_option('datadir') / 'singularity' / 'capabilities'
)

install_data('data/search-providers/dev.sinty.calendar.ini',
  install_dir: get_option('datadir') / 'singularity' / 'search-providers'
)

service_conf = configuration_data()
service_conf.set('bindir', get_option('prefix') / get_option('bindir'))
configure_file(
  input: 'data/dev.sinty.calendar.service.in',
  output: 'dev.sinty.calendar.service',
  configuration: service_conf,
  install: true,
  install_dir: get_option('datadir') / 'dbus-1' / 'services'
)

install_data('data/dev.sinty.calendar.desktop',
  install_dir: get_option('datadir') / 'applications'
)

install_data('data/dev.sinty.calendar.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)

install_data('data/dev.sinty.calendar.json',
  install_dir: get_option('datadir') / 'singularity' / 'app-settings'
)

install_data('data/icons/dev.sinty.calendar.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)
