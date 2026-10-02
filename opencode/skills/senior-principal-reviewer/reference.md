# Reference: Senior Principal Engineer Framework

## Source Document
Based on "Strategic Architecture and Implementation: Defining the Senior Principal Engineer for Innovation and Micronaut Standardization."

## Foundational Frameworks

### SFIA Level 6 (Initiate, Influence)
| Attribute | Expectation |
|-----------|-------------|
| Autonomy | Fully accountable for architectural decisions and innovation strategies |
| Influence | Shapes organization-wide strategy; ensures Micronaut standards adopted universally |
| Complexity | Addresses multifaceted, novel problems involving policy formation |
| Business Skills | Translates complex tech into business value; bridges technical ideals and customer-centric pragmatism |
| Knowledge | Deep JVM ecosystem understanding; drives AOT compilation and reflection-free DI adoption |

### e-CF Lifecycle Areas
1. **PLAN**: Align information systems with business strategy. Identify where Micronaut's lightweight architecture serves business requirements.
2. **BUILD**: Design, engineer, test. Enforce separation of concerns, dependency injection, inversion of control.
3. **RUN**: Design for stability and observability. Health checks, metrics, distributed tracing.
4. **ENABLE**: Mentor colleagues, conduct peer reviews, automate coding standards.
5. **MANAGE**: Governance, risk, compliance. Privacy by Design, data integrity through validation.

### O*NET Cognitive Abilities
- **Deductive Reasoning**: Apply SOLID principles and Hexagonal Architecture to specific problems
- **Inductive Reasoning**: Identify patterns in technical debt across teams; derive organizational standards
- **Problem Sensitivity**: Detect issues (event loop starvation, memory leaks) before production impact
- **Category Flexibility**: Rethink how legacy structures map to modern microservice contexts

## Micronaut Technical Standards

### AOT vs Traditional Reflection
| Aspect | Traditional (Spring Boot) | Micronaut AOT |
|--------|--------------------------|---------------|
| Startup Time | Slow; bound to codebase size | Fast; constant regardless of code size |
| Memory Usage | High; caches reflection metadata | Low; explicit bytecode wiring |
| DI | Runtime reflection | Compile-time ASM/Annotation Processing |
| Error Feedback | Deferred to startup/runtime | Shifted left to compilation |

### Core Technical Protocols
1. **Zero Reflection at Runtime**: Use Micronaut Serde; avoid runtime classpath scanning libraries
2. **Compile-time Validation**: Micronaut Data validates queries at build time
3. **Non-blocking I/O**: `@ExecuteOn(TaskExecutors.BLOCKING)` for JDBC/file I/O
4. **Resilience Patterns**: `@Retryable`, `@CircuitBreaker`, fallback methods
5. **Native Image Support**: GraalVM-ready for serverless/container cold-starts

## Architectural Patterns

### Hexagonal Architecture
- **Domain**: Core business logic, zero framework dependencies
- **Ports**: Interfaces defining input (API) and output (SPI)
- **Adapters**: REST controllers (input), repositories (output)
- **Goal**: Protect business logic from technology churn

### Modular Monolith
- Internal modularity with clean domain-based interfaces
- Single deployment unit initially
- Clear seams for future extraction when KPIs demand it
- Prevents premature "Distributed Monolith" anti-pattern

### YAGNI Principle
- Ground decisions in real requirements, not future assumptions
- Prevents "temptation of complexity"
- Delivers visible results early to build customer trust

## "Invent and Simplify" Practices

### Rule of Three
1. First instance: Write concrete code
2. Second instance: Copy and adapt
3. Third instance: Now extract the abstraction

### Strategic Relocation
- Reassign functionality to its most fitting object-owner
- Move logic to the layer where it naturally belongs

### Senior vs Mid-Level Focus
| Level | Focus | Success Metric |
|-------|-------|----------------|
| Mid-Level | Adding abstractions early; delivering features quickly | Activity: tickets closed, lines written |
| Senior Principal | Defining the problem first; simplifying complexity | Impact: stability, maintainability, reduced future risk |

### Key Questions Before Writing Code
- "Will this be easy to change?"
- "Will this confuse a new team member?"

## Challenging Assumptions

### Behavioral Strategies
1. **Mental Autonomy**: Don't blindly trust directives; question underlying assumptions
2. **Humanize Authority**: Senior figures are fallible; anyone can ask "why?"
3. **Backbone to Disagree and Commit**: Challenge respectfully; commit fully once decided
4. **Contextual Awareness**: Evaluate assumptions about scale, edge cases, blast radius
5. **Solutions with Problems**: Never present a problem without proposed solutions and tradeoffs

## DORA Metrics (Elite Benchmarks)
| Metric | Target |
|--------|--------|
| Deployment Frequency | Multiple per day |
| Lead Time for Changes | < 1 day (ideally < 1 hour) |
| Change Failure Rate | 0-15% |
| Mean Time to Recovery | < 1 hour |
| Reliability | 99.99% uptime, sub-second latency |

## Technical Debt Management

### Debt Categories
- **Reckless/Deliberate**: "We don't have time for design" — Unacceptable
- **Reckless/Inadvertent**: "What's layering?" — Training gap
- **Prudent/Deliberate**: "Ship now, refactor later" — Acceptable with payback plan
- **Prudent/Inadvertent**: "Now we know how we should have done it" — Natural learning

### Three Pillars of Refactoring
1. **Practices**: Maintainable standards, patterns, directory structures
2. **Process**: Peer reviews, pair programming, automated testing
3. **People**: Culture of quality awareness; stakeholders understand debt risks

### Making Refactoring Stick
- **Visible**: Define what needs work
- **Rewarding**: Celebrate cleanup wins in sprint demos
- **Resilient**: Ensure improvements are sustainable
- **Budget**: 10-20% of sprint time for refactoring backlog

## Five Dimensions of Learning Agility
1. **Mental Agility**: Embrace difficult problems; make interdisciplinary connections
2. **People Agility**: Learn from diverse groups; listen before proposing
3. **Change Agility**: Seek new approaches; experiment with emerging tech
4. **Results Agility**: Deliver outcomes amidst unforeseen obstacles
5. **Self-Awareness**: Seek feedback; admit mistakes; always more to learn

## Regulatory and Ethics
- **Privacy by Design**: Data minimization as core principle
- **Regulatory Knowledge**: GDPR, CCPA, HIPAA compliance in architectural choices
- **Security Accountability**: RBAC, JWT validation, secure communication as standard for all APIs
