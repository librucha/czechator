"""Prompts for the synthetic hybrid-Czech corpus. Eval topics are disjoint from
train topics so the hybrid eval set measures generalisation, not recall."""

SYSTEM = """You write realistic Czech workplace text for a training corpus of a \
diacritics-restoration model. Every Czech word must be spelled exactly as a \
careful native writer would spell it, with complete and correct diacritics \
(háčky and čárky). A single missing or wrong accent makes the sample useless. \
Never explain anything; return only the requested JSON."""

HYBRID = {
    "slack_dev": "short messages in a developer team chat (Slack or Teams)",
    "commit": "git commit messages and pull request titles written in Czech",
    "ticket": "Jira ticket titles and short descriptions",
    "code_review": "code review comments",
    "email": "short work e-mails between colleagues",
    "meeting_notes": "meeting notes and action items",
    "incident": "messages during a production incident or an on-call handover",
    "product": "product and design discussion between a PM, a designer and developers",
}

NEGATIVE = {
    "english": "English-only messages from the same kinds of channels (chat, commits, tickets, reviews)",
    "technical": (
        "lines with no natural-language Czech at all: shell commands, file paths, stack trace lines, "
        "identifiers, URLs, version strings, JSON values, log lines"
    ),
}

TOPICS_TRAIN = [
    "frontend build pipeline", "Kubernetes deployment", "PostgreSQL migrations", "payment gateway integration",
    "mobile app release", "CI/CD flakiness", "feature flags rollout", "authentication and SSO",
    "search relevance", "data warehouse ETL", "monitoring and alerting", "API versioning",
    "caching layer", "accessibility fixes", "performance regression", "dependency upgrades",
    "onboarding a new colleague", "sprint planning", "customer bug report", "security audit findings",
    "cloud cost optimisation", "A/B test results", "design system components", "internationalisation",
    "backup and restore", "rate limiting", "GraphQL schema changes", "logging cleanup",
    "invoice generation", "email notifications", "load testing", "infrastructure as code",
]

TOPICS_EVAL = [
    "machine learning model serving", "warehouse inventory system", "video streaming quality",
    "GDPR data deletion request", "legacy monolith split", "printer driver support ticket",
    "hackathon organisation", "on-premise to cloud migration",
]

SCHEMA = {
    "type": "object",
    "properties": {
        "messages": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "text": {"type": "string"},
                    "english_terms": {"type": "array", "items": {"type": "string"}},
                },
                "required": ["text", "english_terms"],
                "additionalProperties": False,
            },
        }
    },
    "required": ["messages"],
    "additionalProperties": False,
}


def user_prompt(category: str, topic: str, n: int) -> str:
    if category in NEGATIVE:
        return (
            f"Write {n} distinct {NEGATIVE[category]} related to: {topic}.\n"
            "They must contain no Czech words and no Czech diacritics.\n"
            "Vary length from a few words to three lines (separate lines with \\n).\n"
            "english_terms: always an empty list."
        )
    return (
        f"Write {n} distinct {HYBRID[category]} related to: {topic}.\n"
        "Requirements:\n"
        "- Czech with complete, correct diacritics.\n"
        "- Mix in English technical terms the way Czech developers really write: English stems with "
        "Czech inflection (mergnout, pushnu, deploynutý, fixnul, commitnout, refaktorovat) and untouched "
        "English terms (pull request, staging, feature flag).\n"
        "- Vary length from three words to three short paragraphs (separate lines with \\n), vary register "
        "from casual to formal, include numbers, identifiers in backticks, file names and URLs where natural.\n"
        "- In about a quarter of casual messages start the first sentence lowercase, as people type in chat.\n"
        "- english_terms: every English word or term exactly as it appears in the text, including "
        "Czech-inflected English stems (e.g. \"mergnul\")."
    )
