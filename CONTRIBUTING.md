# Contributing to singularity-calendar

## Development setup

```bash
git clone https://github.com/singularityos-lab/singularity-calendar
cd singularity-calendar
meson setup build
ninja -C build
```

## Code style

- Language: **Vala** or **C/C++** only.
- Indentation: **4 spaces** no tabs, no trailing whitespace.
- Keep files focused: one primary class per `.vala` file, named after the class.

## License

By contributing you agree your code will be released under [GPL-3.0-only](LICENSE).
