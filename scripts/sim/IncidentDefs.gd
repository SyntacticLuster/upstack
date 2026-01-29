extends RefCounted
class_name IncidentDefs

# Declarative incident and threshold data consumed by Sim.gd.
# No simulation logic should live here.

# ORDER IS LOAD-BEARING: do not reorder INCIDENT_DEFS (determinism depends on array order).
const INCIDENT_DEFS: Array[Dictionary] = [
	{
		"id": "trace_ping",
		"threshold": 15,
		"chance": 0.20,
		"severity": "low",
	},
	{
		"id": "inspection_rumor",
		"threshold": 35,
		"chance": 0.35,
		"severity": "med",
	},
	{
		"id": "targeted_attention",
		"threshold": 60,
		"chance": 0.45,
		"severity": "high",
	},
]

const STRUCTURAL_INCIDENT_DEFS: Array[Dictionary] = [
	{
		"id": "support_shift",
		"level": 0,
		"chance": 0.65,
		"severity": "low",
	},
	{
		"id": "floor_sag",
		"level": 1,
		"chance": 0.40,
		"severity": "med",
	},
	{
		"id": "structural_breach",
		"level": 2,
		"chance": 0.25,
		"severity": "high",
	},
]

const THREAT_THRESHOLDS: Array[int] = [10, 25, 40, 60, 80, 100]
