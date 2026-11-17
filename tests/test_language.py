"""The language the agent is told to answer in (`language_line`).

Run: python3 tests/test_language.py

- a word two of the student's languages share counts for neither: "a"
  and "as" made an English question about "a car, a tram" Portuguese
  (2026-11-17)
- a conversation keeps its language unless a message clearly leads in
  another, so one ambiguous line never flips it
- a clear switch still switches
"""
import importlib.machinery
import importlib.util
import os
import pathlib
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
AGENT = ROOT / "agent" / "longhand-agent"

failures = []


def check(cond, msg):
    print(("ok   " if cond else "FAIL ") + msg)
    if not cond:
        failures.append(msg)


tmp = pathlib.Path(tempfile.mkdtemp(prefix="longhand-language-test-"))
os.environ["XDG_STATE_HOME"] = str(tmp / "state")
os.environ["XDG_CONFIG_HOME"] = str(tmp / "config")
loader = importlib.machinery.SourceFileLoader("longhand_agent_language", str(AGENT))
la = importlib.util.module_from_spec(importlib.util.spec_from_loader("longhand_agent_language", loader))
loader.exec_module(la)

LANGS = ["English", "German", "Portuguese", "Spanish"]
cfg = {"languages": LANGS}


def chosen(line):
    return line.split(" wrote this in ")[1].split(".")[0]


# The message that got a Portuguese answer, alone and inside its conversation.
CAR = "ah, so a static building counts as environmental feature? It's not a car, a tram passing, or so?"
check(la.detect_language(CAR, LANGS) == "English", "the car-and-tram question is English on its own")
earlier = [{"role": "student", "text": "is that a significant difference? So then can one say that the cars, trams, "
                                       "are not as important?"},
           {"role": "agent", "text": "Não, a diferença é pequena."},
           {"role": "student", "text": "ah, so there is a comparison between POV vs SVI: which one does a better "
                                       "job at predicting how stressful an area is?"}]
check(chosen(la.language_line(cfg, CAR, la.said_before(earlier))) == "English",
      "and inside its English conversation")
check("Não" not in la.said_before(earlier), "the agent's own words are not the student's language")

# Each language still recognised on its own.
for text, lang in [("o que é isso? não sei se tenho tempo esta semana", "Portuguese"),
                   ("qué es esto? no tengo tiempo esta semana, pero mañana sí", "Spanish"),
                   ("ich habe diese Woche noch nicht genug Zeit, und du?", "German"),
                   ("what is the deadline for the essay and how long is it?", "English")]:
    check(la.detect_language(text, LANGS) == lang, f"{lang}: {text!r}")

# A short or mixed line keeps the conversation's language...
pt = "não entendi muito bem, você pode explicar como isso funciona?"
check(la.detect_language("ok, a tram?", LANGS, before=pt) == "Portuguese", "a two-word line keeps Portuguese")
check(la.detect_language("SVI vs POV", LANGS, before=pt) == "Portuguese", "no stopwords keeps Portuguese")
# ...and a clear switch still switches.
check(la.detect_language("sorry, can you say that in English? I don't follow the second part", LANGS, before=pt)
      == "English", "a clear English message switches from Portuguese")
check(la.detect_language("e agora, o que eu faço com isso?", LANGS, before=CAR) == "Portuguese",
      "a clear Portuguese message switches from English")

# The first message of a conversation with nothing to go on: the first language.
check(chosen(la.language_line(cfg, "SVI?")) == "English", "nothing to go on: the first language")
check(chosen(la.language_line({"languages": ["Portuguese", "English"]}, "")) == "Portuguese",
      "an empty sample: the first language")
check("never answer in any other language" in la.language_line(cfg, CAR), "the others are still named")

print(f"\n{len(failures)} failure(s)" if failures else "\nall passed")
raise SystemExit(1 if failures else 0)
