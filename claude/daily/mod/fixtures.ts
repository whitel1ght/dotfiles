export const DIARY = `# Thu Oct  8 09:40:02 +03 2026

## habits tracking

- [X] put phone out of sight
- [ ] drawing

## Work

### ECFX

<!-- start-day:start -->
#### Plan

**Meetings:** 10:00 standup · 14:30 retrieve v2 sync

**Merge**
- [ ] merge backend [!6576](https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/6576), then dashboard [!2224](https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2224) (ecfx-9190)

**First**
- [x] review @travisECFX's ecfx-17943 dashboard [!2230](https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2230) · note: approved
- [ ] ecfx-6659 sync with @smtsuchi

**Today**
- [/] ecfx-18169 fix the 3 majors on dashboard [!2231](https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2231) · draft MR [dashboard!2231](https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2231)
- [!] ecfx-17992 Box access question · blocked: waiting on bkeeling
- [>] ecfx-18107 watch for QA feedback

**If time**
- [ ] ecfx-18171 pick up: problems-only filter (utf-8 safe)
<!-- start-day:end -->

<!-- daily-report:start -->
- [ ] not a plan line
<!-- daily-report:end -->
`

export const DIARY_UNPLANNED = DIARY.replace(
  '<!-- start-day:end -->',
  `
**Unplanned**
- [x] ecfx-18200 fix typo in export header · MR [dashboard!2250](https://gitlab.com/ecfx/ecfx-dashboard/-/merge_requests/2250)
- [/] retro prep · note: started the outline
<!-- start-day:end -->`,
)

export const RUN_STATE = `# run-day 2026-10-08
max_agents: 3
- ecfx-18169 | class=auto | agent=a1b2c3 | worktree=/Users/dmitry/projects/worktrees/ecfx-dashboard/ECFX-18169 | mr=ecfx/ecfx-dashboard!2231 | retries=1 | needs_you=yes
- ecfx-18171 | class=auto | agent=- | worktree=- | mr=- | retries=0 | needs_you=no
- ECFX-9190 | class=me
`
