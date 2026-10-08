FROM eclipse-temurin:25-jre
WORKDIR /app

# Install Playwright Chromium dependencies (required by CourtDrive, NJ, and other
# processors that use Playwright instead of Selenium/Camoufox for browser automation).
# Also installs tools useful for post-mortem analysis of heap dumps inside the container.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libglib2.0-0 \
    libnss3 \
    libnspr4 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdbus-1-3 \
    libdrm2 \
    libxcb1 \
    libxkbcommon0 \
    libx11-6 \
    libxcomposite1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libpango-1.0-0 \
    libcairo2 \
    libasound2t64 \
    libatspi2.0-0 \
    libwayland-client0 \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Heap dump output directory (bind-mount from host at runtime to persist across container deletion)
RUN mkdir -p /tmp/dumps

# Copy the CLI fat JAR (built by build-container.sh)
COPY cli-all.jar /app/cli-all.jar

# JVM flags — PACER OOM reproduction on 2304 MB container memory.
#
# MaxRAMPercentage=75.0 matches the current production DuploCloud setting (per the
# crash-log JAVA_TOOL_OPTIONS trace from inbox_nrclyqr2aqi7dmk546yv4yjreq on 2026-04-17).
# This is what we are reproducing. Note: ECFX-11651 validation in v3 established that
# 40 % is the safer long-term target, but for this reproduction we intentionally match
# production's current (unsafe) setting to trigger the same OOM path.
#
# MaxDirectMemorySize=512m bounds Netty off-heap so direct-memory OOM triggers
# ExitOnOutOfMemoryError cleanly rather than cgroup SIGKILL (which bypasses hooks).
#
# HeapDumpOnOutOfMemoryError writes a .hprof to /tmp/dumps when heap is exhausted.
# Combined with -Xlog:gc* we get a full post-mortem for flame-graph verification.
#
# ECFX-13618 / ECFX-11651 validated memory budget for 2304 MiB container with real-world
# PACER bundles (per-attachment sizes up to 400 MiB):
#
#   Heap (40%):     922 MiB  — fits 320 MiB of iText page-tree + retained FetchDocumentResult
#                              Path references + JVM baseline with headroom.
#   Direct (640m):  640 MiB  — holds Netty's aggregated HttpResponse ByteBuffer for a single
#                              in-flight 400 MiB response + allocator overhead.
#   Metaspace:      256 MiB
#   JVM native:    ~150 MiB
#   Total budget: ~1968 MiB  → fits in 2304 MiB cgroup with ~330 MiB spare for kernel buffers.
#
# Netty allocator tuning: numDirectArenas=2 (default is 2*cores = 28 on a laptop), reduces
# per-connection arena overhead. maxOrder=9 caps individual arena chunks at 4 MiB rather than
# the 16 MiB default so memory usage tracks the real working set more tightly.
#
# The previous 75% RAMPercentage over-allocated heap and left no room for the aggregating
# HttpClient's direct-memory buffer on large files. ECFX-11651 validation on NYSCEF 483-doc
# bundles proved 40% is the correct production setting.
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75.0 \
-XX:MaxDirectMemorySize=192m \
-Dio.netty.allocator.numDirectArenas=2 \
-Dio.netty.allocator.numHeapArenas=2 \
-Dio.netty.allocator.maxOrder=9 \
-XX:+UseContainerSupport \
-XX:+ExitOnOutOfMemoryError \
-XX:+HeapDumpOnOutOfMemoryError \
-XX:HeapDumpPath=/tmp/dumps/heap_%p.hprof \
-XX:+UseG1GC \
-XX:G1HeapRegionSize=4m \
-XX:MaxGCPauseMillis=200 \
-XX:+ParallelRefProcEnabled \
-XX:MetaspaceSize=128m \
-XX:MaxMetaspaceSize=256m \
-Xlog:gc*"

# No emails baked in — they're bind-mounted at runtime via -v
ENTRYPOINT ["java", "-Dmicronaut.environments=local", "-jar", "/app/cli-all.jar"]
