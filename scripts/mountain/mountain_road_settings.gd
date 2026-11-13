extends Node3D

@export_group("Percorso")
## Se assegnato, la linea centrale viene letta da questo Path3D (solo a runtime):
## il primo punto e' la partenza, l'ultimo il traguardo.
@export var path: Path3D

@export_group("Strada")
@export var road_width: float = 6.0
@export var road_lift: float = 0.03
## Di quanto l'asfalto visibile sta sotto la superficie fisica su cui rotola l'auto.
## 0.12 e' la differenza che c'e' nelle mappe a tile (ruote a filo dell'asfalto).
@export var asphalt_drop: float = 0.12
@export var rail_height: float = 0.9
@export var rail_offset: float = 0.4
@export var rail_thickness: float = 0.25
@export var rail_friction: float = 0.1
@export var road_friction: float = 1.0

@export_group("Terreno")
@export var terrain_cell: float = 2.0
@export var terrain_margin: float = 60.0
@export var shoulder: float = 2.0
@export var blend_width: float = 8.0
@export var fall_slope: float = 0.6
@export var bed_depth: float = 0.38
@export var skirt_step: int = 3

@export_group("Percorso di prova")
@export var step_length: float = 2.0
@export var flat_start_length: float = 20.0
@export var straight_length: float = 70.0
@export var hairpin_radius: float = 16.0
@export var hairpins: int = 3
@export var straight_grade: float = 0.08
@export var turn_grade: float = 0.05

@export_group("Arco partenza/arrivo")
## Piazza l'arco di track-finish sulla partenza e sul traguardo.
@export var enable_gates: bool = true
## Scala dell'arco (1.0 = dimensioni del tile originale: luce interna 10 m, alto 7 m).
@export var gate_scale: float = 1.0
## Di quanto i piedi dell'arco affondano sotto l'asfalto, per non farli "volare" sui pendii.
@export var gate_sink: float = 0.4

@export_group("Piazzali partenza/arrivo")
## Piazzale di cemento (stile parcheggio) dietro la partenza e oltre il traguardo.
@export var enable_lots: bool = true
## Lato del piazzale quadrato (metri).
@export var lot_size: float = 22.0
## Spessore visibile del bordo del piazzale sotto il piano (metri).
@export var lot_skirt: float = 3.0
@export var lot_color := Color(0.62, 0.62, 0.60)
@export var lot_line_color := Color(0.92, 0.92, 0.88)

@export_group("Aspetto")
@export var asphalt_color := Color(0.25, 0.26, 0.28)
@export var line_color := Color(0.9, 0.9, 0.85)
## Verde base del terreno (sRGB), scelto per stare vicino ai verdi del Nature Kit.
@export var grass_color := Color(0.22, 0.40, 0.16)
## Il terreno varia a chiazze tra erba scura, normale e chiara/secca (0 = tinta unita).
@export_range(0.0, 1.0, 0.05) var grass_variation: float = 0.5
## Tinta delle chiazze piu' chiare e secche.
@export var grass_dry_color := Color(0.38, 0.45, 0.17)
@export var rock_color := Color(0.40, 0.38, 0.34)
@export var rail_color := Color(0.8, 0.8, 0.82)

@export_group("Vegetazione")
## Se abilitata, popola la montagna con alberi e vegetazione
@export var enable_vegetation: bool = true
## Seed del generatore casuale: stesso seed = stessa disposizione degli alberi.
@export var vegetation_seed: int = 12345
## Densita' degli alberi (numero di tentativi di spawn per metro quadro)
@export var tree_density: float = 0.008
## Distanza minima degli alberi dal centro strada (metri)
@export var min_tree_road_distance: float = 6.0
## Distanza minima tra alberi vicini (metri)
@export var min_tree_spacing: float = 3.5
## Pendenza massima del terreno per posizionare alberi (0.0 = piano, 1.0 = 45 gradi)
@export var max_tree_slope: float = 0.8
## Texture colormap (usata per i modelli di vegetazione)
@export var colormap_texture: Texture2D = preload("res://models/Textures/colormap.png")

@export_group("Guardrail")
## Sostituisce il muro pieno con un guardrail (barra a W + pali). Il collider resta quello
## del muro: la fisica non cambia, cambia solo l'aspetto.
@export var enable_guardrails: bool = true
## Un palo ogni N campioni della linea centrale (con step_length 2 m: 2 = un palo ogni 4 m).
@export var guard_post_every: int = 2
## Un catarifrangente ogni N pali.
@export var guard_reflector_every: int = 3
## Emissione dei catarifrangenti (la mappa notturna la alza).
@export var reflector_glow: float = 0.6
@export var post_color := Color(0.42, 0.43, 0.46)

@export_group("Nature Kit")
## Alberi, rocce e vegetazione del Kenney Nature Kit, in aggiunta agli alberi gia' presenti.
@export var enable_nature_kit: bool = true
@export_dir var nature_kit_dir: String = "res://assets/kenney_nature-kit/Models/GLTF format"
## Moltiplicatore della densita' di alberi e vegetazione del Nature Kit.
@export var nature_density: float = 1.0
@export var nature_seed: int = 777
## Distanza minima dal centro strada per gli oggetti del Nature Kit (metri).
@export var nk_min_road_distance: float = 5.5
@export var nk_tree_spacing: float = 3.0
## Profondita' della fascia di alberi ai lati della strada (metri, oltre il guardrail).
@export var nk_tree_band: float = 22.0
@export var nk_tree_chance: float = 0.8
## I modelli del kit sono piccoli (un pino e' ~1.5 m): qui si ingrandiscono.
@export var nk_tree_scale := Vector2(3.0, 5.5)
## Il kit e' esportato con colori non naturali e "unlit": qui i materiali vengono rimappati
## per nome con una palette da montagna (illuminata). Se false, restano quelli originali.
@export var nk_recolor: bool = true
## Rocce nell'interno dei tornanti.
@export var enable_rocks: bool = true
## Lunghezza di strada (metri) su cui si misura quanto si gira per riconoscere un tornante.
@export var hairpin_window: float = 50.0
## Un tratto conta come tornante se il suo raggio medio di curva e' sotto questo valore (metri).
@export var hairpin_max_radius: float = 40.0
## Probabilita' di una roccia per campione e per tentativo nei tornanti.
@export var rock_chance: float = 0.5
@export var rock_scale := Vector2(2.5, 4.5)
## Ciuffi di vegetazione bassa per campione e per lato.
@export var plant_per_sample: float = 3.0
@export var plant_band: float = 10.0
