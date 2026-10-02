#!/usr/bin/env python3
"""Executive-facing visuals for the notice-processing metrics.
Reads data/sessions.pkl (+ data/window.csv) and writes PNGs to out/charts/ plus a
one-page dashboard and a combined PDF deck."""
import os, argparse
import pandas as pd, numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages
import matplotlib.ticker as mticker

_ap = argparse.ArgumentParser()
_ap.add_argument("--exclude-noise", action="store_true",
                 help="drop duplicates & ignored from the entire dataset (de-skew speed metrics)")
EXCL = _ap.parse_args().exclude_noise

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.environ.get("NPM_RUN_DIR", HERE)   # output base, set by run.sh per run
DATA = os.path.join(BASE, "data")
OUT = os.path.join(BASE, "out", "charts_excl_dup_ignored" if EXCL else "charts")
os.makedirs(OUT, exist_ok=True)

# ---- palette ----
GREEN="#2E9E5B"; LGREEN="#7FC8A0"; AMBER="#E8A33D"; RED="#D1495B"; BLUE="#3A6EA5"
GRAY="#9AA3AB"; DGRAY="#5A636B"; PURPLE="#8E6CAF"; INK="#22303C"
plt.rcParams.update({
    "font.family":"DejaVu Sans","font.size":11,"axes.titlepad":18,"axes.titlesize":13,
    "axes.titleweight":"bold","axes.edgecolor":"#CdD3D8","axes.linewidth":0.8,
    "axes.grid":True,"grid.color":"#EAEEF1","grid.linewidth":0.9,
    "axes.axisbelow":True,"figure.facecolor":"white","axes.facecolor":"white",
    "xtick.color":DGRAY,"ytick.color":DGRAY,"text.color":INK,"axes.labelcolor":DGRAY,
})

s = pd.read_pickle(os.path.join(DATA,"sessions.pkl"))
win = pd.read_csv(os.path.join(DATA,"window.csv"))
WLABEL = f"{win.start_utc[0][:16].replace('T',' ')} → {win.end_utc[0][:16].replace('T',' ')} UTC ({int(win.hours[0])}h)"
N = len(s)

# ---- exec grouping of outcomes ----
GROUP = {
    "succeeded_first_try":"Succeeded","succeeded_eventually":"Succeeded",
    "failed_court_fault":"Blocked: court-side","failed_client_action_required":"Blocked: client action",
    "failed_our_fault":"Our error","failed_unclassified":"Pending / unclassified",
    "pending_retryable":"Pending / retrying","pending_waiting_for_stamp":"Pending / retrying",
    "only_delayed_no_attempt":"Not yet processed","duplicate":"Duplicate","ignored":"Ignored",
}
s["group"] = s["outcome"].map(GROUP)
if EXCL:
    # remove duplicates & ignored from the WHOLE dataset so quick no-op items don't skew
    # speed/latency. "Not yet processed" kept (real notices, no completed attempt yet).
    s = s[~s["outcome"].isin(["duplicate", "ignored"])].copy()
    N = len(s)
    WLABEL += "  ·  EXCLUDES duplicates & ignored"
NOISE = {"Duplicate","Ignored","Not yet processed"}
act = s[~s["group"].isin(NOISE)].copy()           # actionable notices (also drops not-yet-processed)
NA = len(act)

# successes only: time-to-success = first attempt start -> final (success) completion, incl. retries
SUCC = act[act["outcome"].isin(["succeeded_first_try","succeeded_eventually"])].copy()
SUCC["tts_ms"] = SUCC["total_residence_ms"]
NS = len(SUCC)

def secs(ms):
    if pd.isna(ms): return "n/a"
    return f"{ms/1000:.1f}s" if ms<60000 else f"{ms/60000:.1f}m"
def pcts(n,d): return f"{100*n/d:.0f}%" if d else "n/a"

def save(fig,name):
    fig.savefig(os.path.join(OUT,name),dpi=190,bbox_inches="tight",facecolor="white")
    plt.close(fig)

# ===================================================================== 1. KPI banner
def kpi_banner(ax=None,standalone=True):
    if standalone: fig,ax = plt.subplots(figsize=(13,2.6))
    ax.axis("off")
    succ = (act["group"]=="Succeeded").sum()
    first = (act["outcome"]=="succeeded_first_try").sum()
    kpis = [
        (f"{NS:,}", "notices successfully\nprocessed", BLUE),
        (pcts(succ,NA), "of actionable\nnotices succeed", GREEN),
        (pcts(first,succ if succ else 1), "of successes are\nfirst-try", GREEN),
        (secs(SUCC["tts_ms"].median()), "median time\nto success", DGRAY),
        (secs(SUCC["tts_ms"].quantile(.9)), "p90 time\nto success", DGRAY),
    ]
    n=len(kpis)
    for i,(big,lab,c) in enumerate(kpis):
        x=(i+0.5)/n
        ax.text(x,0.62,big,ha="center",va="center",fontsize=30,fontweight="bold",color=c)
        ax.text(x,0.20,lab,ha="center",va="center",fontsize=11,color=DGRAY)
        if i: ax.axvline(i/n,0.1,0.9,color="#E3E8EC",lw=1)
    ax.set_title("Notice processing — executive summary    ·    "+WLABEL,
                 loc="left",fontsize=14,color=INK,pad=14)
    if standalone: save(fig,"01_kpi_banner.png")

# ===================================================================== 2. Where notices go (all)
def all_funnel(ax=None,standalone=True):
    if standalone: fig,ax=plt.subplots(figsize=(11,3.2))
    order=["Succeeded","Blocked: court-side","Blocked: client action","Our error",
           "Pending / unclassified","Pending / retrying","Not yet processed","Duplicate","Ignored"]
    cmap={"Succeeded":GREEN,"Blocked: court-side":AMBER,"Blocked: client action":PURPLE,
          "Our error":RED,"Pending / unclassified":"#C9B458","Pending / retrying":"#C9B458",
          "Not yet processed":GRAY,"Duplicate":"#C3CBD1","Ignored":"#D7DDE1"}
    vc=s["group"].value_counts()
    left=0
    for g in order:
        v=int(vc.get(g,0))
        if not v: continue
        ax.barh(0,v,left=left,color=cmap[g],edgecolor="white",height=0.6)
        if v/N>0.03:
            ax.text(left+v/2,0,f"{g}\n{v:,} ({100*v/N:.0f}%)",ha="center",va="center",
                    color="white" if g in("Succeeded","Our error","Blocked: client action") else INK,
                    fontsize=9.5,fontweight="bold")
        left+=v
    ax.set_xlim(0,N); ax.set_ylim(-0.5,0.5); ax.set_yticks([])
    ax.xaxis.set_major_formatter(mticker.FuncFormatter(lambda x,_:f"{int(x/1000)}k"))
    ax.set_title(f"Where all {N:,} notices land — duplicates & ignored dominate raw volume (expected)",loc="left",wrap=True)
    ax.grid(False)
    for sp in ax.spines.values(): sp.set_visible(False)
    if standalone: save(fig,"02_all_outcomes_bar.png")

# ===================================================================== 3. Actionable outcomes
def actionable_bar(ax=None,standalone=True):
    if standalone: fig,ax=plt.subplots(figsize=(9,4.6))
    order=[("Succeeded",GREEN),("Blocked: court-side",AMBER),("Pending / unclassified","#C9B458"),
           ("Blocked: client action",PURPLE),("Our error",RED),("Pending / retrying","#B8A24A")]
    vc=act["group"].value_counts()
    labels=[o for o,_ in order if vc.get(o,0)>0]
    vals=[int(vc.get(o,0)) for o in labels]
    cols=[c for o,c in order if vc.get(o,0)>0]
    y=np.arange(len(labels))[::-1]
    ax.barh(y,vals,color=cols,edgecolor="white")
    for yi,v in zip(y,vals):
        ax.text(v+NA*0.01,yi,f"{v:,}  ({100*v/NA:.0f}%)",va="center",fontsize=10.5,color=INK,fontweight="bold")
    ax.set_yticks(y); ax.set_yticklabels(labels,fontsize=11)
    ax.set_xlim(0,max(vals)*1.22)
    ax.xaxis.set_major_formatter(mticker.FuncFormatter(lambda x,_:f"{int(x/1000)}k"))
    ax.set_title("Actionable notices: working vs. stuck" if not standalone
                 else f"Of {NA:,} actionable notices: what's working vs. what's stuck",loc="left",wrap=True)
    if standalone: ax.text(0,1.02,"(excludes duplicates, ignored, and not-yet-processed)",transform=ax.transAxes,
            fontsize=9,color=GRAY)
    for sp in("top","right","left"): ax.spines[sp].set_visible(False)
    ax.grid(False, axis="y")
    if standalone: save(fig,"03_actionable_outcomes.png")

# ===================================================================== 4. Time to success
def speed_percentiles(ax=None,standalone=True):
    if standalone: fig,ax=plt.subplots(figsize=(9,4.6))
    ft=SUCC[SUCC.outcome=="succeeded_first_try"]["tts_ms"]
    rt=SUCC[SUCC.outcome=="succeeded_eventually"]["tts_ms"]
    groups=[(f"First-try success (n={len(ft.dropna()):,})",ft,GREEN),
            (f"Succeeded after retry (n={len(rt.dropna()):,})",rt,AMBER)]
    q=[.5,.9,.99]; x=np.arange(len(q)); w=0.36
    for i,(lab,ser,c) in enumerate(groups):
        vals=[ser.quantile(qq) for qq in q]
        bars=ax.bar(x+(i-0.5)*w,[v/1000 for v in vals],w,label=lab,color=c,edgecolor="white")
        for b,v in zip(bars,vals):
            ax.text(b.get_x()+b.get_width()/2,(v/1000)*1.06,secs(v),ha="center",va="bottom",
                    fontsize=9.5,fontweight="bold",color=INK)
    ax.set_yscale("log")
    ax.set_xticks(x); ax.set_xticklabels(["p50 (median)","p90","p99"])
    ax.set_ylabel("time to success — seconds (log)")
    ax.set_title("Time to success (first attempt→success)" if not standalone
                 else "Time to a successful result — first-try is seconds; retries stretch to hours",loc="left",wrap=True)
    ax.legend(frameon=False,fontsize=9.5,loc="upper left")
    if standalone: ax.text(1.0,1.02,"retried successes are censored at the 24h window",transform=ax.transAxes,ha="right",fontsize=9,color=GRAY)
    for sp in("top","right"): ax.spines[sp].set_visible(False)
    if standalone: save(fig,"04_time_to_success.png")

# ===================================================================== 5. Slowest processors
def slow_processors(ax=None,standalone=True,topn=15):
    if standalone: fig,ax=plt.subplots(figsize=(9,5.4))
    vol=SUCC.groupby("provider").size()
    big=vol[vol>=50].index
    p90=SUCC[SUCC["provider"].isin(big)].groupby("provider")["tts_ms"].quantile(.9).sort_values(ascending=False).head(topn)
    y=np.arange(len(p90))[::-1]
    cols=[RED if v>300000 else AMBER if v>60000 else GREEN for v in p90.values]   # >5m red, >1m amber
    ax.barh(y,p90.values/1000,color=cols,edgecolor="white")
    for yi,(prov,v) in zip(y,p90.items()):
        ax.text(v/1000+max(p90.values/1000)*0.01,yi,secs(v),va="center",fontsize=9.5,color=INK,fontweight="bold")
    ax.set_yticks(y); ax.set_yticklabels(p90.index,fontsize=9.5)
    ax.set_xlabel("p90 time to success (seconds)")
    ax.set_title("Slowest to a successful result (p90)" if not standalone
                 else "Slowest processors by p90 time-to-success (≥50 successes)",loc="left",wrap=True)
    if standalone: ax.text(0,1.02,"green <1m · amber 1–5m · red >5m",transform=ax.transAxes,fontsize=9,color=GRAY)
    for sp in("top","right","left"): ax.spines[sp].set_visible(False)
    ax.grid(False, axis="y")
    if standalone: save(fig,"05_slowest_to_success.png")

# ===================================================================== 6. Reliability vs volume
def reliability_scatter(ax=None,standalone=True):
    if standalone: fig,ax=plt.subplots(figsize=(9.5,5.6))
    g=act.groupby("provider")
    df=pd.DataFrame({"vol":g.size(),
                     "succ":g.apply(lambda d:(d["group"]=="Succeeded").mean(),include_groups=False)*100})
    df=df[df["vol"]>=150]
    sizes=np.clip(df["vol"]/df["vol"].max()*1400,40,1400)
    cols=[GREEN if v>=80 else AMBER if v>=50 else RED for v in df["succ"]]
    ax.scatter(df["vol"],df["succ"],s=sizes,c=cols,alpha=0.7,edgecolor="white",linewidth=1.2)
    ax.set_xscale("log")
    ax.axhline(80,color=GREEN,ls="--",lw=1,alpha=.6); ax.axhline(50,color=RED,ls="--",lw=1,alpha=.5)
    # label notable points: largest volume + lowest success
    notable=set(df.sort_values("vol",ascending=False).head(6).index)|set(df.sort_values("succ").head(6).index)
    for prov in notable:
        ax.annotate(prov,(df.loc[prov,"vol"],df.loc[prov,"succ"]),fontsize=8.2,color=INK,
                    xytext=(5,4),textcoords="offset points")
    ax.set_xlabel("actionable notice volume (log scale)"); ax.set_ylabel("% succeeded (24h)")
    ax.set_ylim(-3,103)
    ax.set_title("Reliability vs. volume" if not standalone
                 else "Reliability vs. volume — bottom-right = high-volume problem areas",loc="left",wrap=True)
    for sp in("top","right"): ax.spines[sp].set_visible(False)
    if standalone: save(fig,"06_reliability_vs_volume.png")

# ===================================================================== 7. Issue reasons
def issue_reasons(ax=None,standalone=True):
    if standalone: fig,ax=plt.subplots(figsize=(9,4.4))
    reasons=[("Court hasn't assigned /\nfind case (waits on court)",int((s["outcome"]=="failed_court_fault").sum()),AMBER),
             ("Client action needed\n(credentials / jurisdiction)",int((s["outcome"]=="failed_client_action_required").sum()),PURPLE),
             ("Waiting for stamped doc",int(s["ever_waiting_for_stamp"].sum()),BLUE),
             ("Our errors\n(server / parse / storage)",int((s["outcome"]=="failed_our_fault").sum()),RED)]
    reasons.sort(key=lambda r:r[1],reverse=True)
    labs=[r[0] for r in reasons]; vals=[r[1] for r in reasons]; cols=[r[2] for r in reasons]
    y=np.arange(len(labs))[::-1]
    ax.barh(y,vals,color=cols,edgecolor="white")
    for yi,v in zip(y,vals):
        ax.text(v+max(vals)*0.01,yi,f"{v:,}",va="center",fontsize=10.5,fontweight="bold",color=INK)
    ax.set_yticks(y); ax.set_yticklabels(labs,fontsize=10)
    ax.set_xlim(0,max(vals)*1.18)
    ax.set_title("What's holding notices up" if not standalone
                 else "What's holding notices up — most blockers are court- or client-side, not ours",loc="left",wrap=True)
    for sp in("top","right","left"): ax.spines[sp].set_visible(False)
    ax.grid(False, axis="y")
    if standalone: save(fig,"07_issue_reasons.png")

# ===================================================================== 8. First-try by top processor
def firsttry_by_proc(ax=None,standalone=True,topn=12):
    if standalone: fig,ax=plt.subplots(figsize=(9,5.2))
    vol=act.groupby("provider").size().sort_values(ascending=False).head(topn).index
    g=act[act["provider"].isin(vol)].groupby("provider")
    ft=(g.apply(lambda d:(d["outcome"]=="succeeded_first_try").mean(),include_groups=False)*100)
    ev=(g.apply(lambda d:(d["outcome"]=="succeeded_eventually").mean(),include_groups=False)*100)
    ft=ft.reindex(vol); ev=ev.reindex(vol)
    y=np.arange(len(vol))[::-1]
    ax.barh(y,ft.values,color=GREEN,edgecolor="white",label="first try")
    ax.barh(y,ev.values,left=ft.values,color=LGREEN,edgecolor="white",label="eventually")
    for yi,f,e in zip(y,ft.values,ev.values):
        ax.text(f+e+1,yi,f"{f+e:.0f}%",va="center",fontsize=9.5,fontweight="bold",color=INK)
    ax.set_yticks(y); ax.set_yticklabels(vol,fontsize=9.5)
    ax.set_xlim(0,100); ax.set_xlabel("% of actionable notices succeeding")
    ax.set_title("Success rate by processor" if not standalone
                 else "Success rate by top processor (first-try vs. eventual)",loc="left",wrap=True)
    ax.legend(frameon=False,fontsize=9.5,loc="lower right")
    for sp in("top","right","left"): ax.spines[sp].set_visible(False)
    ax.grid(False, axis="y")
    if standalone: save(fig,"08_firsttry_by_processor.png")

# ===================================================================== 9. Successes by processor (counts)
def successes_by_proc(ax=None,standalone=True,topn=15):
    if standalone: fig,ax=plt.subplots(figsize=(9.5,5.6))
    vol=SUCC.groupby("provider").size().sort_values(ascending=False).head(topn)
    g=SUCC[SUCC["provider"].isin(vol.index)].groupby("provider")
    ft=g.apply(lambda d:(d.outcome=="succeeded_first_try").sum(),include_groups=False).reindex(vol.index)
    ev=g.apply(lambda d:(d.outcome=="succeeded_eventually").sum(),include_groups=False).reindex(vol.index)
    y=np.arange(len(vol))[::-1]
    ax.barh(y,ft.values,color=GREEN,edgecolor="white",label="first try")
    ax.barh(y,ev.values,left=ft.values,color=AMBER,edgecolor="white",label="after retry")
    for yi,f,e in zip(y,ft.values,ev.values):
        ax.text(f+e+vol.max()*0.01,yi,f"{int(f+e):,}"+(f"  ({int(e):,} retried)" if e else ""),
                va="center",fontsize=9,fontweight="bold",color=INK)
    ax.set_yticks(y); ax.set_yticklabels(vol.index,fontsize=9.5)
    ax.set_xlim(0,vol.max()*1.25); ax.set_xlabel("successful notices")
    ax.set_title("Successes by processor" if not standalone
                 else "Successful notices by processor (first-try vs. after-retry)",loc="left",wrap=True)
    ax.legend(frameon=False,fontsize=9.5,loc="lower right")
    for sp in("top","right","left"): ax.spines[sp].set_visible(False)
    ax.grid(False, axis="y")
    if standalone: save(fig,"09_successes_by_processor.png")

# ===================================================================== 10. Time-to-success by processor
def tts_by_proc(ax=None,standalone=True,topn=15):
    if standalone: fig,ax=plt.subplots(figsize=(9.5,5.6))
    vol=SUCC.groupby("provider").size()
    big=vol[vol>=50].index
    g=SUCC[SUCC["provider"].isin(big)].groupby("provider")["tts_ms"]
    med=g.median(); p90=g.quantile(.9)
    order=med.sort_values(ascending=False).head(topn).index
    med=med.reindex(order); p90=p90.reindex(order)
    y=np.arange(len(order)); h=0.38
    ax.barh(y+h/2,med.values/1000,h,color=BLUE,edgecolor="white",label="median")
    ax.barh(y-h/2,p90.values/1000,h,color="#A9C2DD",edgecolor="white",label="p90")
    for yi,v in zip(y+h/2,med.values): ax.text(v/1000*1.02,yi,secs(v),va="center",fontsize=8.5,color=INK)
    for yi,v in zip(y-h/2,p90.values): ax.text(v/1000*1.02,yi,secs(v),va="center",fontsize=8.5,color=DGRAY)
    ax.set_yticks(y); ax.set_yticklabels(order,fontsize=9.5)
    ax.set_xscale("log"); ax.set_xlabel("time to success — seconds (log)")
    ax.set_title("Time to success by processor" if not standalone
                 else "Time to success by processor — median & p90 (≥50 successes)",loc="left",wrap=True)
    ax.legend(frameon=False,fontsize=9.5,loc="lower right")
    for sp in("top","right","left"): ax.spines[sp].set_visible(False)
    ax.grid(False, axis="y")
    if standalone: save(fig,"10_tts_by_processor.png")

# ---- per-processor success breakdown TABLE ----
def write_success_table():
    rows=[]
    for prov,g in SUCC.groupby("provider"):
        tts=g["tts_ms"].dropna()
        q=lambda p:(tts.quantile(p) if len(tts) else np.nan)
        rows.append(dict(provider=prov, successes=len(g),
            first_try=int((g.outcome=="succeeded_first_try").sum()),
            after_retry=int((g.outcome=="succeeded_eventually").sum()),
            pct_first_try=round(100*(g.outcome=="succeeded_first_try").mean(),1),
            tries_avg=round(g["n_tries"].mean(),2), tries_max=int(g["n_tries"].max()),
            tts_median_ms=round(q(.5),0), tts_p90_ms=round(q(.9),0), tts_p99_ms=round(q(.99),0),
            tts_avg_ms=round(tts.mean(),0) if len(tts) else np.nan,
            tts_std_ms=round(tts.std(ddof=0),0) if len(tts) else np.nan))
    df=pd.DataFrame(rows).sort_values("successes",ascending=False)
    base=os.path.dirname(OUT)
    df.to_csv(os.path.join(base,"success_by_processor.csv"),index=False)
    with pd.ExcelWriter(os.path.join(base,"success_by_processor.xlsx"),engine="openpyxl") as xw:
        df.to_excel(xw,sheet_name="success_by_processor",index=False)
    # markdown for console / report
    def secs(ms): return "n/a" if pd.isna(ms) else (f"{ms/1000:.1f}s" if ms<60000 else f"{ms/60000:.1f}m")
    md=["| processor | successes | first-try | after-retry | %first-try | avg tries | median TTS | p90 TTS | p99 TTS |",
        "|---|--:|--:|--:|--:|--:|--:|--:|--:|"]
    for _,r in df.head(25).iterrows():
        md.append(f"| {r['provider']} | {int(r['successes']):,} | {int(r['first_try']):,} | {int(r['after_retry']):,} | "
                  f"{r['pct_first_try']:.0f}% | {r['tries_avg']:.1f} | {secs(r['tts_median_ms'])} | {secs(r['tts_p90_ms'])} | {secs(r['tts_p99_ms'])} |")
    open(os.path.join(base,"success_by_processor.md"),"w").write("\n".join(md)+"\n")
    return df

STAB = write_success_table()

# ---- render all standalone ----
for fn in [kpi_banner,all_funnel,actionable_bar,speed_percentiles,slow_processors,
           reliability_scatter,issue_reasons,firsttry_by_proc,successes_by_proc,tts_by_proc]:
    fn()

# ---- one-page dashboard ----
with plt.rc_context({"axes.titlesize":11,"axes.titlepad":10,"font.size":9.5,
                     "xtick.labelsize":8.5,"ytick.labelsize":8.5}):
    fig=plt.figure(figsize=(19,12))
    gs=fig.add_gridspec(3,3,height_ratios=[0.5,1,1],hspace=0.62,wspace=0.34)
    kpi_banner(fig.add_subplot(gs[0,:]),standalone=False)
    actionable_bar(fig.add_subplot(gs[1,0]),standalone=False)
    speed_percentiles(fig.add_subplot(gs[1,1]),standalone=False)
    issue_reasons(fig.add_subplot(gs[1,2]),standalone=False)
    slow_processors(fig.add_subplot(gs[2,0]),standalone=False)
    reliability_scatter(fig.add_subplot(gs[2,1]),standalone=False)
    firsttry_by_proc(fig.add_subplot(gs[2,2]),standalone=False)
    fig.savefig(os.path.join(OUT,"00_dashboard.png"),dpi=170,bbox_inches="tight",facecolor="white")
    plt.close(fig)

# ---- combined PDF deck ----
with PdfPages(os.path.join(OUT,"notice_processing_exec_deck.pdf")) as pdf:
    for name in ["00_dashboard.png"]:
        pass
    for fn in [kpi_banner,all_funnel,actionable_bar,speed_percentiles,slow_processors,
               reliability_scatter,issue_reasons,firsttry_by_proc,successes_by_proc,tts_by_proc]:
        fig=plt.figure(figsize=(11,6.2)); ax=fig.add_subplot(111)
        fn(ax,standalone=False); pdf.savefig(fig,bbox_inches="tight"); plt.close(fig)

print("charts written to", OUT)
for f in sorted(os.listdir(OUT)): print("  ",f)
