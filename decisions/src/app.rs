//! All state and key handling. `update` is the whole behaviour: an event and the time in,
//! the new state and the commands for `main` to run out. Nothing here touches the
//! terminal, the clock or `decide`.

use std::collections::HashMap;

use crate::queue::Decision;

pub const UNDO_MS: i64 = 5_000;
pub const GHOST_MS: i64 = 200;
pub const FLIP_MS: i64 = 300;
pub const TOAST_MS: i64 = 3_000;
const HALF_PAGE: u16 = 10;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Key {
    Char(char),
    Enter,
    Esc,
    Up,
    Down,
    Space,
    Backspace,
    CtrlD,
    CtrlU,
    Interrupt,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Event {
    Key(Key),
    Tick,
    Changed,
    Loaded(Result<Vec<Decision>, String>),
    Sent { id: String, result: Result<(), String> },
    Signal,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Command {
    Reload,
    Answer { id: String, n: u8, note: Option<String> },
    Ask { id: String, text: String },
    OpenUrl(String),
    Quit,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Band {
    Fresh,
    Warm,
    Old,
    Stale,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Anim {
    Deal,
    Next,
    Prev,
    Throw,
    Arrive(String),
    Leave(String),
    AgeBand { id: String, from: Band, to: Band },
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum Side {
    #[default]
    Front,
    Back,
}

#[derive(Debug, Clone, PartialEq)]
pub enum InputKind {
    Note,
    Ask { id: String },
}

#[derive(Debug, Clone, PartialEq)]
pub struct Input {
    pub kind: InputKind,
    pub text: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Pending {
    pub decision: Decision,
    pub n: u8,
    pub note: Option<String>,
    pub due: i64,
    pub paused: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Failed {
    pub n: u8,
    pub note: Option<String>,
    pub error: String,
}

#[derive(Debug, Default)]
pub struct State {
    pub queue: Vec<Decision>,
    pub cur: usize,
    pub side: Side,
    pub cursor: Option<usize>,
    pub scroll: u16,
    pub scroll_max: u16,
    pub skipped: Vec<String>,
    pub pending: Option<Pending>,
    pub sending: HashMap<String, Pending>,
    pub failed: HashMap<String, Failed>,
    pub input: Option<Input>,
    pub help: bool,
    pub error: Option<String>,
    pub toast: Option<(String, i64)>,
    pub ghost: Option<(Decision, i64)>,
    pub flip: Option<i64>,
    pub anims: Vec<Anim>,
    pub bands: HashMap<String, Band>,
    pub now: i64,
    pub loaded: bool,
    pub quitting: bool,
}

pub fn band(age_ms: i64) -> Band {
    match age_ms / 60_000 {
        ..15 => Band::Fresh,
        15..60 => Band::Warm,
        60..180 => Band::Old,
        _ => Band::Stale,
    }
}

pub fn age_label(age_ms: i64) -> String {
    let m = age_ms.max(0) / 60_000;
    if m < 60 { format!("{m}m") } else { format!("{}h {:02}m", m / 60, m % 60) }
}

impl State {
    pub fn new(now: i64) -> Self {
        Self { now, ..Self::default() }
    }

    pub fn current(&self) -> Option<&Decision> {
        self.queue.get(self.cur)
    }

    pub fn age_ms(&self, d: &Decision) -> i64 {
        d.asked_ms().map_or(0, |at| (self.now - at).max(0))
    }

    pub fn oldest_ms(&self) -> i64 {
        self.queue.iter().map(|d| self.age_ms(d)).max().unwrap_or(0)
    }

    /// The flip or a thrown card's ghost is on screen, so frames are needed.
    pub fn animating(&self) -> bool {
        self.ghost.is_some() || self.flip.is_some()
    }

    fn toast(&mut self, msg: String) {
        self.toast = Some((msg, self.now + TOAST_MS));
    }

    fn reset_view(&mut self) {
        self.side = Side::Front;
        self.cursor = None;
        self.scroll = 0;
    }
}

pub fn update(s: &mut State, ev: Event, now: i64) -> Vec<Command> {
    s.now = now;
    let mut out = Vec::new();
    match ev {
        Event::Tick => tick(s, &mut out),
        Event::Changed => out.push(Command::Reload),
        Event::Loaded(Ok(list)) => loaded(s, list),
        Event::Loaded(Err(e)) => s.error = Some(e),
        Event::Sent { id, result } => sent(s, id, result),
        Event::Signal => quit(s, &mut out),
        Event::Key(k) => key(s, k, &mut out),
    }
    out
}

fn tick(s: &mut State, out: &mut Vec<Command>) {
    if s.pending.as_ref().is_some_and(|p| !p.paused && s.now >= p.due) {
        send_pending(s, out);
    }
    if s.ghost.as_ref().is_some_and(|(_, until)| s.now >= *until) {
        s.ghost = None;
    }
    if s.flip.is_some_and(|t| s.now - t >= FLIP_MS) {
        s.flip = None;
    }
    if s.toast.as_ref().is_some_and(|(_, until)| s.now >= *until) {
        s.toast = None;
    }
    track_bands(s);
}

fn track_bands(s: &mut State) {
    let bands: Vec<(String, Band)> = s.queue.iter().map(|d| (d.id.clone(), band(s.age_ms(d)))).collect();
    for (id, to) in bands {
        if let Some(from) = s.bands.insert(id.clone(), to) {
            if from != to {
                s.anims.push(Anim::AgeBand { id, from, to });
            }
        }
    }
}

fn loaded(s: &mut State, list: Vec<Decision>) {
    s.error = None;
    let first = !s.loaded;
    s.loaded = true;
    let before: Vec<String> = s.queue.iter().map(|d| d.id.clone()).collect();
    let cur_id = s.current().map(|d| d.id.clone());
    let held: Vec<String> = s.pending.iter().map(|p| p.decision.id.clone()).chain(s.sending.keys().cloned()).collect();
    let mut list: Vec<Decision> = list.into_iter().filter(|d| !held.contains(&d.id)).collect();
    s.skipped.retain(|id| list.iter().any(|d| &d.id == id));
    list.sort_by_key(|d| {
        if s.failed.contains_key(&d.id) {
            (0, 0)
        } else if let Some(i) = s.skipped.iter().position(|id| id == &d.id) {
            (2, i)
        } else {
            (1, 0)
        }
    });
    let ids: Vec<String> = list.iter().map(|d| d.id.clone()).collect();
    if first {
        s.anims.push(Anim::Deal);
    } else {
        for id in ids.iter().filter(|id| !before.contains(id)) {
            s.anims.push(Anim::Arrive(id.clone()));
        }
        if let Some(gone) = cur_id.as_ref().filter(|c| !ids.contains(c)) {
            s.anims.push(Anim::Leave(gone.clone()));
            if s.side == Side::Back {
                s.toast(format!("{gone} was closed elsewhere"));
            }
            s.reset_view();
        }
    }
    s.queue = list;
    let keep = cur_id.and_then(|c| s.queue.iter().position(|d| d.id == c));
    s.cur = keep.unwrap_or(s.cur.min(s.queue.len().saturating_sub(1)));
    track_bands(s);
}

fn key(s: &mut State, k: Key, out: &mut Vec<Command>) {
    if k == Key::Interrupt {
        return quit(s, out);
    }
    if s.input.is_some() {
        return input_key(s, k, out);
    }
    if s.help {
        s.help = false;
        return;
    }
    match k {
        Key::Char('q') => quit(s, out),
        Key::Esc if s.side == Side::Back => flip(s),
        Key::Esc => quit(s, out),
        Key::Char('o') => open(s, out),
        Key::Char('r') => out.push(Command::Reload),
        Key::Char('?') => s.help = true,
        Key::Space => flip(s),
        _ if s.side == Side::Back => back_key(s, k),
        _ => front_key(s, k, out),
    }
}

fn front_key(s: &mut State, k: Key, _out: &mut Vec<Command>) {
    let last = s.queue.len().saturating_sub(1);
    match k {
        Key::Char('j') => go(s, s.cur + 1),
        Key::Char('k') if s.cur > 0 => go(s, s.cur - 1),
        Key::Char('g') => go(s, 0),
        Key::Char('G') => go(s, last),
        Key::Down | Key::Up => {
            let Some(d) = s.current() else { return };
            let max = d.options.len().saturating_sub(1);
            s.cursor = Some(match (k, s.cursor) {
                (Key::Down, None) => 0,
                (Key::Down, Some(c)) => (c + 1).min(max),
                (_, None) => max,
                (_, Some(c)) => c.saturating_sub(1),
            });
        }
        Key::Char('s') => skip(s),
        _ => {}
    }
}

fn back_key(s: &mut State, k: Key) {
    s.scroll = match k {
        Key::Char('j') | Key::Down => s.scroll.saturating_add(1).min(s.scroll_max),
        Key::Char('k') | Key::Up => s.scroll.saturating_sub(1),
        Key::CtrlD => s.scroll.saturating_add(HALF_PAGE).min(s.scroll_max),
        Key::CtrlU => s.scroll.saturating_sub(HALF_PAGE),
        Key::Char('g') => 0,
        Key::Char('G') => s.scroll_max,
        _ => s.scroll,
    };
}

fn go(s: &mut State, idx: usize) {
    if idx >= s.queue.len() || idx == s.cur {
        return;
    }
    s.anims.push(if idx > s.cur { Anim::Next } else { Anim::Prev });
    s.cur = idx;
    s.reset_view();
}

fn flip(s: &mut State) {
    if s.current().is_none() {
        return;
    }
    s.side = match s.side {
        Side::Front => Side::Back,
        Side::Back => Side::Front,
    };
    s.flip = Some(s.now);
    s.scroll = 0;
}

fn skip(s: &mut State) {
    if s.queue.len() < 2 {
        return;
    }
    let d = s.queue.remove(s.cur);
    s.skipped.retain(|id| id != &d.id);
    s.skipped.push(d.id.clone());
    s.queue.push(d);
    if s.cur == s.queue.len() - 1 {
        s.cur = 0;
    }
    s.reset_view();
    s.anims.push(Anim::Next);
}

fn open(s: &mut State, out: &mut Vec<Command>) {
    let Some(d) = s.current() else { return };
    if d.mr.is_empty() {
        let msg = format!("no MR on {}", d.id);
        s.toast(msg);
    } else {
        out.push(Command::OpenUrl(d.mr.clone()));
    }
}

fn quit(s: &mut State, out: &mut Vec<Command>) {
    s.quitting = true;
    out.push(Command::Quit);
}

// Answering lives in Task 3; these stubs keep Task 2 compiling.
fn input_key(_s: &mut State, _k: Key, _out: &mut Vec<Command>) {}
fn sent(_s: &mut State, _id: String, _result: Result<(), String>) {}
fn send_pending(_s: &mut State, _out: &mut Vec<Command>) {}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::queue::decode;

    pub const T0: i64 = 1_792_483_448_000;
    pub const MIN: i64 = 60_000;

    pub fn fixture() -> Vec<Decision> {
        decode(include_str!("../tests/fixtures/list.json")).unwrap()
    }

    /// D-1 from the fixture, then D-2..D-n copied from the fixture's D-2.
    pub fn many(n: usize) -> Vec<Decision> {
        (1..=n)
            .map(|i| {
                let mut d = fixture()[usize::from(i > 1)].clone();
                d.id = format!("D-{i}");
                d
            })
            .collect()
    }

    pub fn loaded(list: Vec<Decision>) -> State {
        let mut s = State::new(T0);
        update(&mut s, Event::Loaded(Ok(list)), T0);
        s.anims.clear();
        s
    }

    pub fn press(s: &mut State, k: Key) -> Vec<Command> {
        let now = s.now;
        update(s, Event::Key(k), now)
    }

    fn ids(s: &State) -> Vec<&str> {
        s.queue.iter().map(|d| d.id.as_str()).collect()
    }

    #[test]
    fn first_load_deals_the_deck() {
        let mut s = State::new(T0);
        assert!(update(&mut s, Event::Loaded(Ok(fixture())), T0).is_empty());
        assert_eq!(ids(&s), ["D-1", "D-2"]);
        assert_eq!(s.current().unwrap().id, "D-1");
        assert_eq!(s.anims, [Anim::Deal]);
    }

    #[test]
    fn j_and_k_move_between_cards_and_stop_at_the_ends() {
        let mut s = loaded(many(3));
        press(&mut s, Key::Char('k'));
        assert_eq!(s.cur, 0);
        assert!(s.anims.is_empty());
        press(&mut s, Key::Char('j'));
        press(&mut s, Key::Char('j'));
        press(&mut s, Key::Char('j'));
        assert_eq!(s.cur, 2);
        assert_eq!(s.anims, [Anim::Next, Anim::Next]);
        press(&mut s, Key::Char('k'));
        assert_eq!(s.cur, 1);
        assert_eq!(s.anims.last(), Some(&Anim::Prev));
    }

    #[test]
    fn g_and_shift_g_jump_to_the_ends() {
        let mut s = loaded(many(4));
        press(&mut s, Key::Char('G'));
        assert_eq!(s.cur, 3);
        press(&mut s, Key::Char('g'));
        assert_eq!(s.cur, 0);
    }

    #[test]
    fn arrows_move_the_option_cursor_within_the_options() {
        let mut s = loaded(fixture());
        press(&mut s, Key::Down);
        assert_eq!(s.cursor, Some(0));
        for _ in 0..5 {
            press(&mut s, Key::Down);
        }
        assert_eq!(s.cursor, Some(2));
        press(&mut s, Key::Up);
        assert_eq!(s.cursor, Some(1));
        press(&mut s, Key::Char('j'));
        assert_eq!(s.cursor, None, "a new card starts without a cursor");
    }

    #[test]
    fn space_flips_and_the_back_scrolls_within_its_max() {
        let mut s = loaded(fixture());
        press(&mut s, Key::Space);
        assert_eq!(s.side, Side::Back);
        assert_eq!(s.flip, Some(T0));
        s.scroll_max = 12;
        press(&mut s, Key::Char('j'));
        assert_eq!(s.scroll, 1);
        press(&mut s, Key::CtrlD);
        assert_eq!(s.scroll, 11);
        press(&mut s, Key::CtrlD);
        assert_eq!(s.scroll, 12);
        press(&mut s, Key::Char('g'));
        assert_eq!(s.scroll, 0);
        press(&mut s, Key::Char('G'));
        assert_eq!(s.scroll, 12);
        press(&mut s, Key::CtrlU);
        assert_eq!(s.scroll, 2);
        assert_eq!(s.cur, 0, "j/g/G scroll on the back, they do not change cards");
    }

    #[test]
    fn esc_on_the_back_flips_to_the_front_instead_of_quitting() {
        let mut s = loaded(fixture());
        press(&mut s, Key::Space);
        assert!(press(&mut s, Key::Esc).is_empty());
        assert_eq!(s.side, Side::Front);
    }

    #[test]
    fn the_flip_ends_after_flip_ms() {
        let mut s = loaded(fixture());
        press(&mut s, Key::Space);
        update(&mut s, Event::Tick, T0 + FLIP_MS - 1);
        assert!(s.animating());
        update(&mut s, Event::Tick, T0 + FLIP_MS);
        assert!(!s.animating());
    }

    #[test]
    fn skip_moves_the_card_to_the_end_and_a_reload_keeps_it_there() {
        let mut s = loaded(many(3));
        press(&mut s, Key::Char('s'));
        assert_eq!(ids(&s), ["D-2", "D-3", "D-1"]);
        assert_eq!(s.current().unwrap().id, "D-2");
        update(&mut s, Event::Loaded(Ok(many(3))), T0);
        assert_eq!(ids(&s), ["D-2", "D-3", "D-1"]);
        assert_eq!(s.current().unwrap().id, "D-2");
    }

    #[test]
    fn skipping_the_last_card_goes_back_to_the_first() {
        let mut s = loaded(many(2));
        press(&mut s, Key::Char('j'));
        press(&mut s, Key::Char('s'));
        assert_eq!(s.cur, 0);
    }

    #[test]
    fn a_reload_keeps_the_same_card_in_front() {
        let mut s = loaded(many(3));
        press(&mut s, Key::Char('j'));
        let mut list = many(3);
        list.insert(0, { let mut d = list[2].clone(); d.id = "D-9".into(); d });
        update(&mut s, Event::Loaded(Ok(list)), T0);
        assert_eq!(s.current().unwrap().id, "D-2");
        assert!(s.anims.contains(&Anim::Arrive("D-9".into())));
    }

    #[test]
    fn a_card_closed_elsewhere_leaves_and_the_next_one_takes_its_place() {
        let mut s = loaded(many(3));
        press(&mut s, Key::Char('j'));
        press(&mut s, Key::Space);
        s.anims.clear();
        let mut list = many(3);
        list.remove(1);
        update(&mut s, Event::Loaded(Ok(list)), T0);
        assert_eq!(s.current().unwrap().id, "D-3");
        assert_eq!(s.side, Side::Front);
        assert_eq!(s.anims, [Anim::Leave("D-2".into())]);
        assert_eq!(s.toast.as_ref().unwrap().0, "D-2 was closed elsewhere");
    }

    #[test]
    fn a_failed_read_keeps_the_queue_and_the_next_good_one_clears_the_error() {
        let mut s = loaded(fixture());
        update(&mut s, Event::Loaded(Err("decide not runnable".into())), T0);
        assert_eq!(s.queue.len(), 2);
        assert_eq!(s.error.as_deref(), Some("decide not runnable"));
        update(&mut s, Event::Loaded(Ok(fixture())), T0);
        assert_eq!(s.error, None);
    }

    #[test]
    fn changed_files_and_r_ask_for_a_reload() {
        let mut s = loaded(fixture());
        assert_eq!(update(&mut s, Event::Changed, T0), [Command::Reload]);
        assert_eq!(press(&mut s, Key::Char('r')), [Command::Reload]);
    }

    #[test]
    fn o_opens_the_mr_or_says_there_is_none() {
        let mut s = loaded(fixture());
        assert_eq!(press(&mut s, Key::Char('o')), [Command::OpenUrl("https://gitlab.com/ecfx/ecfx-backend/-/merge_requests/870".into())]);
        press(&mut s, Key::Char('j'));
        assert!(press(&mut s, Key::Char('o')).is_empty());
        assert_eq!(s.toast.as_ref().unwrap().0, "no MR on D-2");
        update(&mut s, Event::Tick, T0 + TOAST_MS);
        assert_eq!(s.toast, None);
    }

    #[test]
    fn help_opens_with_a_question_mark_and_any_key_closes_it_without_acting() {
        let mut s = loaded(many(2));
        press(&mut s, Key::Char('?'));
        assert!(s.help);
        press(&mut s, Key::Char('j'));
        assert!(!s.help);
        assert_eq!(s.cur, 0);
    }

    #[test]
    fn bands_and_labels() {
        assert_eq!(band(14 * MIN), Band::Fresh);
        assert_eq!(band(15 * MIN), Band::Warm);
        assert_eq!(band(60 * MIN), Band::Old);
        assert_eq!(band(180 * MIN), Band::Stale);
        assert_eq!(age_label(59 * MIN + 59_999), "59m");
        assert_eq!(age_label(65 * MIN), "1h 05m");
        assert_eq!(age_label(-5 * MIN), "0m");
    }

    #[test]
    fn future_or_bad_asked_is_age_zero() {
        let mut list = fixture();
        list[0].asked = "2026-10-21T11:04:08+03:00".into();
        list[1].asked = "soon".into();
        let s = loaded(list);
        assert_eq!(s.age_ms(&s.queue[0]), 0);
        assert_eq!(s.age_ms(&s.queue[1]), 0);
        assert_eq!(band(s.age_ms(&s.queue[0])), Band::Fresh);
    }

    #[test]
    fn crossing_an_age_band_animates_once() {
        let mut s = loaded(fixture());
        update(&mut s, Event::Tick, T0 + 14 * MIN);
        assert!(s.anims.is_empty());
        update(&mut s, Event::Tick, T0 + 15 * MIN);
        assert!(s.anims.contains(&Anim::AgeBand { id: "D-1".into(), from: Band::Fresh, to: Band::Warm }));
        s.anims.clear();
        update(&mut s, Event::Tick, T0 + 16 * MIN);
        assert!(s.anims.is_empty());
    }
}
