Want to contribute? Great! First, read this page (including the small print at the end).

### Intro
If you care about the performance of real-world JavaScript and you'd like to help us make Octane even more representative of what needs to be fast on the web, we'd love your help!

If you think Octane's performance test coverage doesn't cover something important and you identified an open source JavaScript application that could cover the gap, then send it our way by [filing an issue](https://github.com/chromium/octane/issues) and we might consider it for a future update of Octane.

As a rule of thumb, the application should be decomposed in an initialization phase, a function that performs a "step" of calculation and that will be called in a tight loop, and a cleanup function. The "step" function shall not be too long , ideally in the tens/hundred ms range. The code from initialization to cleanup is then called a minimum of up to 32 times and the time spent averaged. Ideally we try to keep each test reasonably fast, in the order of few seconds.

### Before you contribute
Before we can use your code, you must sign the
[Google Individual Contributor License Agreement](https://developers.google.com/open-source/cla/individual?csw=1)
(CLA), which you can do online. The CLA is necessary mainly because you own the
copyright to your changes, even after your contribution becomes part of our
codebase, so we need your permission to use and distribute your code. We also
need to be sure of various other things—for instance that you'll tell us if you
know that your code infringes on other people's patents. You don't have to sign
the CLA until after you've submitted your code for review and a member has
approved it, but you must do it before we can put your code into our codebase.
Before you start working on a larger contribution, you should get in touch with
us first through the issue tracker with your idea so that we can help out and
possibly guide you. Coordinating up front makes it much easier to avoid
frustration later on.

### Code reviews
All submissions, including submissions by project members, require review. We
use Github pull requests for this purpose.

### The small print
Contributions made by corporations are covered by a different agreement than
the one above, the Software Grant and Corporate Contributor License Agreement.
