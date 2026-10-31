# duo-hinge

Vendored from https://github.com/tosbaha/duo-fold-control (MIT, see LICENSE-duo-hinge).
Sets the iPhone Duo simulator hinge angle via the private HID event Device Hub uses.
Test automation only; may break with Xcode updates.

    clang -fobjc-arc -framework Foundation -o duo-hinge duo-hinge.m
    ./duo-hinge -d <UDID> closed|half|flat|0-180
