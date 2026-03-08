# Vision: XRoads Chambre des Metiers

## Constat

XRoads remplit son role premier : orchestrer des agents IA pour developper des applications from scratch (PRD -> code -> tests -> merge).

Mais l'infrastructure (slots, layers, dependances, failover, merge) est generique. Elle peut orchestrer **n'importe quel pipeline metier**, pas seulement du code.

## Pivot

| Aujourd'hui | Demain |
|-------------|--------|
| Orchestrateur pour **developpeurs** | Orchestrateur pour **metiers** |
| PRD -> code -> tests -> merge | Brief -> livrables metier -> assets finaux |
| Skills = outils de dev | Skills = competences metier |
| Loops = boucles de code | Loops = boucles de production |
| Livrables = commits | Livrables = contenus, images, videos, docs |

## Preuve de concept : vibe-marketing

Les 16 skills `~/.claude/skills/vibe-marketing/` forment deja un pipeline metier complet :

```
Layer 0 (Fondation):
  01-brand-voice
  02-positioning-angles
  03-keyword-research

Layer 1 (Contenu textuel):
  04-lead-magnet          (depends: 01, 02)
  05-direct-response-copy (depends: 01, 02)
  06-seo-content          (depends: 01, 03)

Layer 2 (Distribution):
  07-newsletter           (depends: 04, 06)
  08-email-sequences      (depends: 05)
  09-content-atomizer     (depends: 06, 07)

Layer 3 (Strategie):
  10-orchestrator         (depends: 09)
  11-creative-strategist  (depends: 01, 02, 10)

Layer 4 (Assets visuels):
  12-image-generation     (depends: 11)
  13-product-photography  (depends: 11)
  14-social-graphics      (depends: 11, 12)

Layer 5 (Video):
  15-product-video        (depends: 13, 14)
  16-talking-head         (depends: 11, 15)
```

## Abstraction manquante : "Metier"

Un **Metier** (ou SkillPack) encapsule :

1. **Domaine** : Marketing, E-commerce, SaaS, Design, Legal, etc.
2. **Skills** : pipeline ordonne de competences (les 16 skills marketing par ex.)
3. **Loops** : scripts de boucle specifiques au metier (pas forcement du code)
4. **Templates PRD** : briefs adaptes au metier (brief marketing vs feature spec)
5. **Livrables** : type de sortie (articles, emails, images vs commits)
6. **Agents preferes** : Claude pour redaction, Gemini pour SEO/analyse, etc.

## Architecture cible

```
MetierRegistry
  ├── marketing/
  │   ├── metier.json          (definition, skills, layers)
  │   ├── templates/           (brief templates)
  │   ├── loops/               (marketing-specific loops)
  │   └── skills/              (16 vibe-marketing skills)
  ├── ecommerce/
  ├── saas/
  └── design/

MetierDispatcher (like DebugDispatcher)
  Brief -> generateMetierPRD() -> PRDDocument -> LayeredDispatcher
```

## Infra existante reutilisable

- LayeredDispatcher : layers + dependances + parallelisme
- SlotAssignment : agents par slot
- StatusMonitor : polling completions
- LoopLauncher : worktree + AGENT.md + skills injection
- Failover : rate-limit handling
- Merge : coordination post-completion

## Prochaines etapes

1. Definir le modele `Metier` (struct Swift)
2. Creer `MetierRegistry` (decouverte auto des metiers installes)
3. Creer `MetierDispatcher` (genere PRD metier -> LayeredDispatcher)
4. Adapter LoopLauncher pour loops non-code (pas de worktree git, livrables dans output/)
5. UI : selecteur de metier dans le dashboard
6. Premier metier complet : Marketing (les 16 skills existent deja)
