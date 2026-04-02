# XRoads — Motion Design Brief

> Video de présentation produit · 45–60 secondes · Style: cinematic tech, dark UI showcase

---

## Concept Créatif

**Titre**: *"One Brain. Six Agents. Zero Chaos."*

**Mood**: Dark, futuriste, précis. Chaque mouvement est intentionnel. On ne montre pas un outil — on montre un cockpit de commandement pour développeurs. Le rythme oscille entre lenteur contemplative (zooms lents sur l'interface) et accélération brutale (agents qui se lancent, code qui défile).

**Références visuelles**: Tron Legacy UI, Westworld control room, Apple keynote product shots (ralenti + focus rack), GitHub Universe motion graphics.

---

## Palette Vidéo

| Élément | Valeur |
|---------|--------|
| Background | Noir profond (#0a0a0f → #0d1117) |
| Accent principal | Neon green (#0DF170) + Claude blue (#388bfd) |
| Accent secondaire | Neon purple (#8B5CF6), Gold (#d29922) |
| Texte overlay | Monospace blanc (#e6edf3), opacity pulsée |
| Particules | Neon cyan (#00D4FF), magenta (#FF33CC) |

---

## Musique & Sound Design

**Track**: Électronique minimale, tempo 90-110 BPM. Style Rival Consoles, Kiasmos, ou Ólafur Arnalds avec beats discrets. Montée progressive.

**Sound FX**:
- Boot sound: low-frequency hum crescendo
- Agent launch: digital chirp + whoosh
- Brain pulse: deep bass throb
- Terminal typing: soft mechanical keystrokes
- Success: harmonic chime (majeur)
- Connection synapse: electrical crackle léger

---

## Storyboard

### SEQ 01 — Cold Open (0:00 – 0:05)

**Shot 1.1** — Noir complet. Un point neon cyan apparaît au centre. Il pulse lentement.
- Camera: statique, centré
- Animation: point lumineux 4px → glow expand → reveal neural filaments
- Sound: deep hum, rising

**Shot 1.2** — Les filaments se déploient en réseau neural. Le cerveau XRoads se matérialise.
- Camera: léger zoom out (1.05x → 1.0x), 2 secondes
- Animation: NeonBrainView s'anime — gyri pulsent, ring d'énergie tourne
- Text overlay: aucun

**Shot 1.3** — Le cerveau s'illumine pleinement. Flash blanc subtil.
- Camera: statique
- Animation: brightness peak, puis settle into idle state
- Transition: le fond noir révèle l'interface complète

---

### SEQ 02 — The Dashboard Reveal (0:05 – 0:15)

**Shot 2.1** — Zoom out fluide depuis le cerveau → vue complète du dashboard hexagonal.
- Camera: dolly zoom out continu (3s), légère rotation 3D (-2° → 0°)
- Animation: les 6 slot cards apparaissent un par un (stagger 0.15s), séquence horaire depuis le slot nord
- Sound: whoosh discret à chaque slot, ambient pad

**Shot 2.2** — Les connexions synaptiques s'allument entre le brain et chaque slot.
- Camera: statique, plein écran dashboard
- Animation: SynapseConnections — dashed lines animate du centre vers chaque slot, dot pulse à l'arrivée
- Sound: electrical crackle × 6, rapide

**Shot 2.3** — Texte overlay apparaît en fondu.
- Camera: statique
- Text overlay (bottom-left, monospace): `// orchestrate your agents`
- Duration: 2s hold

---

### SEQ 03 — Agent Launch Sequence (0:15 – 0:28)

**Shot 3.1** — Zoom in sur le Slot 1 (Claude). L'utilisateur configure l'agent.
- Camera: ease-in zoom vers slot card (scale 1x → 2.5x), centré sur le slot
- Animation: SlotConfigDialog apparaît (scale-in 0.15s). On voit la sélection: Agent = Claude, Action = Implement, Skill = code-reviewer
- Sound: UI click sounds

**Shot 3.2** — L'agent se lance. Le slot passe de "empty" à "running".
- Camera: maintenu sur le slot zoomé
- Animation: StatusBadge passe gris → vert avec pulse. Le border du slot card pulse en bleu Claude (#388bfd). Terminal text commence à défiler.
- Sound: digital chirp + whoosh de lancement

**Shot 3.3** — Cut rapide: montage de 3 agents se lançant simultanément.
- Camera: cuts rapides (0.5s chacun) sur les slots 2 (Gemini, gold border), 3 (Codex, green border), retour vue globale
- Animation: chaque slot s'active — borders glow, terminals défilent, brain central intensifie sa rotation
- Sound: 3 chirps rapides en séquence ascendante (Do-Mi-Sol), rythme accéléré

**Shot 3.4** — Vue d'ensemble : 4 agents actifs, brain orchestrating.
- Camera: zoom out lent vers dashboard complet
- Animation: toutes les synapses pulsent, le cerveau est en état "monitoring" (vert #3fb950), les CostBadges s'incrémentent en temps réel
- Text overlay: `4 agents · 3 worktrees · 1 brain`
- Sound: ambient groove s'installe, beat subtil 100 BPM

---

### SEQ 04 — The Cockpit (0:28 – 0:38)

**Shot 4.1** — Le panneau Cockpit slide in depuis la droite.
- Camera: léger pan vers la droite, le dashboard se compresse
- Animation: CockpitPanel entre en slide-right (0.25s). On voit: Brain consciousness stream, Chairman feed, Budget panel
- Sound: panel slide SFX

**Shot 4.2** — Zoom in sur le CockpitBrainPanelView. Le cerveau "parle".
- Camera: zoom in 1x → 1.8x sur le brain panel
- Animation: messages de conscience défilent en temps réel — le cerveau explique sa stratégie. Texte monospace vert sur fond noir, typing effect.
- Exemple de texte: `> distributing feature/auth to Claude-1... reviewing conflicts on slot-3... cost: $0.42`
- Sound: soft typing clicks

**Shot 4.3** — ApprovalCardView apparaît. Le cerveau demande l'approbation humaine.
- Camera: centré sur l'approval card
- Animation: la card scale-in avec un glow amber (#d29922). Boutons "Approve" et "Reject" pulsent doucement. Risk badge visible.
- Sound: attention chime (deux notes ascendantes)

**Shot 4.4** — L'utilisateur approuve. Flash vert.
- Camera: statique
- Animation: bouton Approve pressé → flash vert → card dismiss → slot reprend l'exécution
- Sound: success chime harmonique

---

### SEQ 05 — Intelligence & Merge (0:38 – 0:48)

**Shot 5.1** — Split screen: code en train d'être écrit vs. diff review.
- Camera: écran coupé en deux, léger parallax
- Animation: côté gauche — terminal avec code défilant (syntax highlighted). Côté droit — git diff avec lignes vertes/rouges.
- Sound: typing acceleré, beat monte

**Shot 5.2** — Le cerveau passe en mode "synthesizing" (violet #bc8cff).
- Camera: retour sur le dashboard, zoom sur le brain
- Animation: le cerveau change de couleur → violet, les anneaux d'énergie accélèrent, des particules convergent vers le centre
- Sound: bass throb profond + synthé montant

**Shot 5.3** — Merge réussi. Le cerveau passe en "celebrating" (or #ffd700).
- Camera: léger zoom out avec shake subtil (1px, 0.1s)
- Animation: explosion de particules dorées depuis le cerveau. Tous les slots flash vert simultanément. SynapseConnections brillent intensément.
- Sound: success chord majeur (3 notes), particles sparkle SFX

**Shot 5.4** — ReviewOverlay apparaît avec le résumé.
- Camera: overlay centré, fond blur
- Animation: ReviewOverlay scale-in. Métriques visibles: "6 files changed", "0 conflicts", "$1.23 total cost", "3 agents completed"
- Sound: UI appear, ambient redescend

---

### SEQ 06 — The Tagline (0:48 – 0:55)

**Shot 6.1** — L'interface fade out progressivement. Le cerveau reste seul, pulsant.
- Camera: statique, centré
- Animation: tout l'UI fade (opacity 1 → 0 sur 2s) sauf le NeonBrain central qui pulse calmement
- Sound: musique redescend, reverb trail

**Shot 6.2** — Texte final apparaît en fondu.
- Camera: statique
- Text overlay (centré, monospace, 24px semibold):

```
X R O A D S
```
- Sous-titre (14px, text-secondary, 0.5s après):
```
One Brain. Six Agents. Zero Chaos.
```

- Animation: lettre par lettre (stagger 0.05s), glow apparaît derrière le texte
- Sound: final note sustained, fade to silence

---

### SEQ 07 — End Card (0:55 – 1:00)

**Shot 7.1** — Logo XRoads + call to action.
- Camera: statique
- Animation: le brain se miniaturise en icône logo. URL apparaît en dessous.
- Text: `github.com/… · Built with SwiftUI & Tauri`
- Sound: silence ou dernier click subtil

---

## Spécifications Techniques

| Paramètre | Valeur |
|-----------|--------|
| Résolution | 3840 × 2160 (4K) |
| FPS | 60fps (smooth UI animations) |
| Format | MP4 (H.265) + ProRes pour masters |
| Durée | 55–60 secondes |
| Aspect ratio | 16:9 |
| Sous-titres | Non (texte intégré au motion) |

---

## Transitions entre séquences

| De → Vers | Type | Durée |
|-----------|------|-------|
| SEQ 01 → 02 | Zoom out continu | 1.5s |
| SEQ 02 → 03 | Cut on action | 0s (hard cut) |
| SEQ 03 → 04 | Slide panel in | 0.25s |
| SEQ 04 → 05 | Split screen wipe | 0.3s |
| SEQ 05 → 06 | Fade to brain | 2s |
| SEQ 06 → 07 | Scale down + fade | 1s |

---

## Éléments à capturer / animer

### Captures d'écran à réaliser (écran réel)
1. Dashboard complet avec 6 slots actifs
2. Slot config dialog ouvert
3. Cockpit panel avec brain consciousness
4. Approval card en attente
5. Terminal avec code en défilement
6. Review overlay avec métriques
7. Brain en chaque état (idle, running, merging, celebrating)

### Éléments à post-produire
1. Particules neon (After Effects / Motion)
2. Glow et bloom sur les accents
3. Camera moves (zoom, pan, dolly) en post
4. Text overlays monospace avec timing précis
5. Synapse connections accentuées
6. Sound design layers

---

## Notes de Direction Artistique

- **Pas de voix off**. La vidéo parle par ses visuels et son texte overlay.
- **Chaque frame doit être un screenshot digne de landing page.** Pas de frame "transitoire" laide.
- **Le rythme est roi.** Les cuts suivent le beat. Les animations commencent sur les temps forts.
- **Monospace partout.** Même les overlays de texte utilisent la même font que l'app.
- **La lumière vient de l'interface.** Pas de source lumineuse externe. L'UI éclaire le vide autour d'elle.
- **Respiration.** Entre les séquences d'action (SEQ 03, 04, 05), laisser 1-2s de calme pour que l'oeil absorbe.
- **Le cerveau est le personnage principal.** Chaque séquence commence ou finit sur lui. Il est le fil rouge narratif.
