# Third-Party Notices

MIGHTY is BSD-3-Clause (see `LICENSE`). It includes code adapted from the
projects below, which remain under their own licenses.

## GCOPTER — MIT

- `include/mighty/lbfgs.hpp` is adapted from
  [ZJU-FAST-Lab/GCOPTER](https://github.com/ZJU-FAST-Lab/GCOPTER)
  (`gcopter/include/gcopter/lbfgs.hpp`); `src/mighty/lbfgs_solver.cpp` and
  `include/mighty/lbfgs_solver.hpp` build on it.

```
MIT License

Copyright(c) 2021 Zhepei Wang (wangzhepei@live.com) and Fei Gao (fgaoaa@zju.edu.cn)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## jps3d — BSD-3-Clause

- `src/hgp/graph_search.cpp`, `include/hgp/graph_search.hpp` and
  `include/hgp/map_util.hpp` contain code derived from
  [sikang/jps3d](https://github.com/sikang/jps3d) (`src/jps_planner/graph_search.cpp`,
  `include/jps_collision/map_util.h`), substantially modified.

```
BSD 3-Clause License

Copyright (c) 2017, sikang
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

* Neither the name of the copyright holder nor the names of its
  contributors may be used to endorse or promote products derived from
  this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## motion_primitive_library — Apache-2.0

- `include/hgp/read_map.hpp` is a modified version of
  [sikang/motion_primitive_library](https://github.com/sikang/motion_primitive_library)
  `test/read_map.hpp`. License text: `licenses/Apache-2.0.txt`.

## Files that carry their own notices

- `include/hgp/termcolor.hpp` — termcolor, © 2013 Ihor Kalnytskyi, BSD-3-Clause.
- `include/sim/exprtk.hpp` — C++ Mathematical Expression Toolkit, © Arash Partow, MIT.
- `include/sim/ImuSensorPlugin.hh`, `src/sim/gazebo_ros_imu_sensor.cpp` —
  © Open Source Robotics Foundation, Apache-2.0 (`licenses/Apache-2.0.txt`).
