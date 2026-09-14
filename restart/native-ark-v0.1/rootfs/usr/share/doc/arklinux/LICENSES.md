# ARKlinux Licenses & Open Source Notices

ARKlinux combines project-specific components with third-party open-source software. A license that applies to one component does not automatically apply to the complete distribution.

## ARKlinux components

ARKlinux components use their own repository and per-file license declarations. ARKlinux Shell source files carrying `SPDX-License-Identifier: Apache-2.0` are licensed under the Apache License 2.0.

Do not infer a blanket license for a project-specific file that does not carry an applicable license declaration.

## Third-party software

Third-party software bundled with ARKlinux retains its original upstream license. ARKlinux does not replace or relicense those terms.

The authoritative package-provided license texts installed on the system are located under:

`/usr/share/licenses`

Package-declared license identifiers can also be inspected with:

`pacman -Qi <package>`

## Distribution notice

ARKlinux branding, project-specific source, models, documentation, operating-system packages, and other artifacts may have different license terms. Review the license and notices supplied with each component before redistribution or modification.
