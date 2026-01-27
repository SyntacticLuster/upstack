extends RefCounted
class_name IncidentDefs

# Declarative incident and threshold data consumed by Sim.gd.
# No simulation logic should live here.

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

const THREAT_THRESHOLDS: Array[int] = [10, 25, 40, 60, 80, 100]

