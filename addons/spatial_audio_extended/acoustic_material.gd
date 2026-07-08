@tool
@icon("images/acoustic_material.svg")
extends Resource
class_name AcousticMaterial
## Defines how a surface interacts with sound — absorption, scattering, and
## transmission.
## [br][br]
## [b]Absorption[/b] — fraction of sound energy absorbed on reflection
## (used by reverb / room estimation). Higher = less reverberant surface.
## [br][b]Scattering[/b] — how diffusely the surface reflects sound.
## [code]0.0[/code] = perfect mirror, [code]1.0[/code] = fully diffuse.
## [br][b]Transmission[/b] — fraction of sound energy that passes through
## the surface (used by occlusion). [code]0.0[/code] = fully blocks,
## [code]1.0[/code] = fully transparent. Three bands model
## frequency-dependent behaviour:
## [br]  • [b]Low[/b]  ≤ 400 Hz
## [br]  • [b]Mid[/b]  400 – 2 500 Hz
## [br]  • [b]High[/b] ≥ 2 500 Hz
## [br][b]Total Absorption[/b] — when enabled, this surface behaves as
## soundproof in occlusion (fully blocks direct sound) and strongly suppresses
## reverb wetness.

#region EXPORTS (editable properties)

@export_group("Absorption")
## Fraction of low-frequency energy absorbed on reflection (≤ 400 Hz).
@export_range(0.0, 1.0, 0.01) var absorption_low : float = 0.10
## Fraction of mid-frequency energy absorbed on reflection (400 – 2 500 Hz).
@export_range(0.0, 1.0, 0.01) var absorption_mid : float = 0.20
## Fraction of high-frequency energy absorbed on reflection (≥ 2 500 Hz).
@export_range(0.0, 1.0, 0.01) var absorption_high : float = 0.30

@export_group("Scattering")
## How diffusely the surface reflects sound.
## [code]0.0[/code] = specular reflection, [code]1.0[/code] = fully scattered.
@export_range(0.0, 1.0, 0.01) var scattering : float = 0.05

@export_group("Transmission")
## Fraction of low-frequency energy that passes through (≤ 400 Hz).
## [code]0.0[/code] = fully blocks, [code]1.0[/code] = fully transparent.
@export_range(0.0, 1.0, 0.001) var transmission_low : float = 0.100
## Fraction of mid-frequency energy that passes through (400 – 2 500 Hz).
@export_range(0.0, 1.0, 0.001) var transmission_mid : float = 0.050
## Fraction of high-frequency energy that passes through (≥ 2 500 Hz).
@export_range(0.0, 1.0, 0.001) var transmission_high : float = 0.030

@export_group("Special")
## Treat this material as soundproof for direct-path occlusion and reverb.
@export var total_absorption : bool = false
## Fade speed used when entering/leaving total-absorption occlusion.
## Lower values make soundproof transitions less abrupt.
@export_range(0.1, 20.0, 0.1) var total_absorption_transition_speed : float = 2.5

#endregion

#region PRESETS (common real-world materials)

static func preset_generic() -> AcousticMaterial:
	var m := AcousticMaterial.new()
	m.absorption_low = 0.10; m.absorption_mid = 0.20; m.absorption_high = 0.30
	m.scattering = 0.05
	m.transmission_low = 0.100; m.transmission_mid = 0.050; m.transmission_high = 0.030
	return m

static func preset_brick() -> AcousticMaterial:
	var m := AcousticMaterial.new()
	m.absorption_low = 0.03; m.absorption_mid = 0.04; m.absorption_high = 0.07
	m.scattering = 0.05
	m.transmission_low = 0.025; m.transmission_mid = 0.019; m.transmission_high = 0.010
	return m

static func preset_concrete() -> AcousticMaterial:
	var m := AcousticMaterial.new()
	m.absorption_low = 0.05; m.absorption_mid = 0.07; m.absorption_high = 0.08
	m.scattering = 0.05
	m.transmission_low = 0.015; m.transmission_mid = 0.011; m.transmission_high = 0.008
	return m

static func preset_ceramic() -> AcousticMaterial:
	var m := AcousticMaterial.new()
	m.absorption_low = 0.01; m.absorption_mid = 0.02; m.absorption_high = 0.02
	m.scattering = 0.05
	m.transmission_low = 0.060; m.transmission_mid = 0.044; m.transmission_high = 0.011
	return m

static func preset_gravel() -> AcousticMaterial:
	var m := AcousticMaterial.new()
	m.absorption_low = 0.60; m.absorption_mid = 0.70; m.absorption_high = 0.80
	m.scattering = 0.60
	m.transmission_low = 0.031; m.transmission_mid = 0.012; m.transmission_high = 0.008
	return m

static func preset_carpet() -> AcousticMaterial:
	var m := AcousticMaterial.new()
	m.absorption_low = 0.24; m.absorption_mid = 0.69; m.absorption_high = 0.73
	m.scattering = 0.57
	m.transmission_low = 0.020; m.transmission_mid = 0.005; m.transmission_high = 0.003
	return m

static func preset_glass() -> AcousticMaterial:
	var m := AcousticMaterial.new()
	m.absorption_low = 0.25; m.absorption_mid = 0.06; m.absorption_high = 0.03
	m.scattering = 0.05
	m.transmission_low = 0.060; m.transmission_mid = 0.044; m.transmission_high = 0.011
	return m

static func preset_plaster() -> AcousticMaterial:
	var m := AcousticMaterial.new()
	m.absorption_low = 0.12; m.absorption_mid = 0.06; m.absorption_high = 0.04
	m.scattering = 0.05
	m.transmission_low = 0.056; m.transmission_mid = 0.028; m.transmission_high = 0.004
	return m

static func preset_wood() -> AcousticMaterial:
	var m := AcousticMaterial.new()
	m.absorption_low = 0.11; m.absorption_mid = 0.07; m.absorption_high = 0.06
	m.scattering = 0.05
	m.transmission_low = 0.070; m.transmission_mid = 0.014; m.transmission_high = 0.005
	return m

static func preset_metal() -> AcousticMaterial:
	var m := AcousticMaterial.new()
	m.absorption_low = 0.20; m.absorption_mid = 0.07; m.absorption_high = 0.06
	m.scattering = 0.05
	m.transmission_low = 0.200; m.transmission_mid = 0.025; m.transmission_high = 0.010
	return m

static func preset_rock() -> AcousticMaterial:
	var m := AcousticMaterial.new()
	m.absorption_low = 0.13; m.absorption_mid = 0.20; m.absorption_high = 0.24
	m.scattering = 0.20
	m.transmission_low = 0.015; m.transmission_mid = 0.002; m.transmission_high = 0.001
	return m

static func preset_acoustic_foam() -> AcousticMaterial:
	var m := AcousticMaterial.new()
	m.absorption_low = 1.00; m.absorption_mid = 1.00; m.absorption_high = 1.00
	m.scattering = 0.60
	m.transmission_low = 0.000; m.transmission_mid = 0.000; m.transmission_high = 0.000
	m.total_absorption = true
	m.total_absorption_transition_speed = 1.2
	return m
#endregion
