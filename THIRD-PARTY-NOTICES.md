# Third-party notices

Czechator links these libraries statically, so a distributed binary contains
their code and carries their licence terms with it.

## swift-argument-parser 1.8.2

<https://github.com/apple/swift-argument-parser> — Apache License 2.0

Copyright Apple Inc. and the Swift project authors.

Licensed under the Apache License, Version 2.0. You may obtain a copy of the
licence at <http://www.apache.org/licenses/LICENSE-2.0>. Unless required by
applicable law or agreed to in writing, software distributed under the licence
is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
KIND, either express or implied.

The full text ships with the dependency at
`.build/checkouts/swift-argument-parser/LICENSE.txt` after a build.

## Yams 5.4.0

<https://github.com/jpsim/Yams> — MIT License

Copyright (c) 2016 JP Simard.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the above copyright notice and this permission notice being included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.

The full text ships with the dependency at `.build/checkouts/Yams/LICENSE` after
a build.

## libyaml, vendored inside Yams

Yams bundles the C YAML parser **libyaml** (`Sources/CYaml`), which is
MIT-licensed upstream. The vendored source carries no separate notice; the single
`LICENSE` at the root of the Yams repository covers it, and that file is the one
referenced above.
