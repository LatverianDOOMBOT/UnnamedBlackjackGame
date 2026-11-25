extends Node3D
class_name BlackJackManager

var card_scene = preload("res://card.tscn")
@export var Table: Node3D

var cards = []
var shoe = []
var discarded_cards = []

var dealerdemon = preload("res://Scenes/demon_1.tscn")
var demon2 = preload("res://Scenes/demon_2.tscn")
var demon3 = preload("res://Scenes/demon_3.tscn")
var demon4 = preload("res://Scenes/demon_4.tscn")
var demon5 = preload("res://Scenes/demon_5.tscn")
var player = preload("res://Scenes/player.tscn")

enum DEMONS {DEALER, DEMON1, DEMON2, DEMON3, DEMON4}

var participants = {
	dealerdemon: {"Node": null, "PositionNode": null, "Cards": [], "value_of_cards": 0, "TurnTaken": false},
	demon2: {"Node": null, "PositionNode": null, "Cards": [], "value_of_cards": 0, "TurnTaken": false},
	demon3: {"Node": null, "PositionNode": null, "Cards": [], "value_of_cards": 0, "TurnTaken": false},
	demon4: {"Node": null, "PositionNode": null, "Cards": [], "value_of_cards": 0, "TurnTaken": false},
	demon5: {"Node": null, "PositionNode": null, "Cards": [], "value_of_cards": 0, "TurnTaken": false},
	player: {"Node": null, "PositionNode": null, "Cards": [], "value_of_cards": 0, "TurnTaken": false}
}

var tableScene = preload("res://Scenes/test_room.tscn")

var demonsPlaying = [dealerdemon]
var demonsNotPlaying = [demon2, demon3, demon4, demon5]
var demon_at_spawn = {}

# Opponents, then dealer, then human player.
var turnList = [demon4, demon5, demon3, demon2, dealerdemon, player]

var roundOngoing: bool = false
var roundComplete: bool = false
var player_bust: bool = false
var game_won: bool = false

var npc_phase_complete: bool = false
var npc_phase_running: bool = false
var final_duel_round: bool = false
var dealer_bust: bool = false

# Tweak these in the Inspector to control how long the audience
# can see the cards and results before characters disappear.
@export_range(0.1, 5.0, 0.1) var npc_action_delay: float = 0.9
@export_range(0.1, 5.0, 0.1) var result_display_delay: float = 2.5
@export_range(0.0, 5.0, 0.1) var death_animation_delay: float = 0.8
@export var play_demon_death_animation: bool = true
@export var result_label_height: float = 2.0
@export var status_label_font_size: int = 40
@export_range(0.001, 0.1, 0.001) var status_label_pixel_size: float = 0.012

# Labels are true 3D scene nodes parented to their characters.
# High transparent render priority draws them over a typical
# full-screen spatial shader; the outline uses the next priority down.
# The full-screen material's render_priority must be below 126.
var status_labels = {}  # participant PackedScene -> Label3D


# --------------------------------------------------
# CARD RANKS: ALWAYS USE RANK, NOT THE NODE NAME
# --------------------------------------------------

func _rank_from_text(raw: String) -> String:
	# Supports filenames such as hearts_A, A_spades, clubs_10,
	# king_of_hearts, spades_J, and numeric ranks 1-13.
	var clean = raw.get_file().get_basename().to_upper()
	for separator in ["-", " ", ".", "(", ")", "[", "]"]:
		clean = clean.replace(separator, "_")

	for token in clean.split("_", false):
		match token:
			"A", "ACE":
				return "A"
			"J", "JACK":
				return "J"
			"Q", "QUEEN":
				return "Q"
			"K", "KING":
				return "K"
			"T", "TEN":
				return "10"

		if token.is_valid_int():
			var number = int(token)
			if number == 1:
				return "A"
			if number >= 2 and number <= 10:
				return str(number)
			if number == 11:
				return "J"
			if number == 12:
				return "Q"
			if number == 13:
				return "K"

	return ""


func _card_rank(card: Node) -> String:
	if card.has_meta("blackjack_rank"):
		return str(card.get_meta("blackjack_rank"))

	var rank = _rank_from_text(card.name)
	if rank != "":
		return rank

	# Fallback for cards instantiated elsewhere. Prefer the filename
	# metadata above: numeric value 11 alone cannot identify an ace.
	var value_property = card.get("value")
	if value_property != null:
		return _rank_from_text(str(value_property))

	return ""


func calculate_hand_value(participant) -> bool:
	var total = 0
	var aces = 0

	for card in participants[participant]["Cards"]:
		var rank = _card_rank(card)
		if rank == "":
			push_error("Cannot identify rank for card: " + str(card.name) + ". Check the texture filename / card.gd.")
			return false

		if rank == "A":
			total += 11
			aces += 1
		elif rank == "J" or rank == "Q" or rank == "K":
			total += 10
		else:
			total += int(rank)

	while total > 21 and aces > 0:
		total -= 10
		aces -= 1

	participants[participant]["value_of_cards"] = total
	return true


func _is_blackjack(participant) -> bool:
	return participants[participant]["Cards"].size() == 2 and participants[participant]["value_of_cards"] == 21


func _print_hand(participant):
	var who = "PLAYER"
	if participant == dealerdemon:
		who = "DEALER"
	elif participant != player:
		who = str(participants[participant]["Node"].name)

	var ranks = PackedStringArray()
	for card in participants[participant]["Cards"]:
		ranks.append(_card_rank(card))

	print(who, " | cards: [", ", ".join(ranks), "] | total: ", participants[participant]["value_of_cards"])


# --------------------------------------------------
# SHOE / CARDS
# --------------------------------------------------

func create_card(type: String, color: String, value: String):
	var card_node = card_scene.instantiate()
	add_child(card_node)
	card_node.set_card(type, color, value)
	card_node.hide()

	var rank = _rank_from_text(value)
	if rank != "":
		card_node.set_meta("blackjack_rank", rank)
	else:
		push_error("Unrecognized card rank: " + value)

	shoe.append(card_node)


func new_shoe():
	if roundOngoing:
		push_warning("Cannot rebuild the shoe during an active round.")
		return

	# Free every previous card exactly once.
	var old_cards = shoe.duplicate()
	for card in discarded_cards:
		if not old_cards.has(card):
			old_cards.append(card)
	for participant in participants.keys():
		for card in participants[participant]["Cards"]:
			if not old_cards.has(card):
				old_cards.append(card)

	for card in old_cards:
		if is_instance_valid(card):
			card.queue_free()

	shoe.clear()
	discarded_cards.clear()
	cards.clear()

	for participant in participants.keys():
		participants[participant]["Cards"] = []
		participants[participant]["value_of_cards"] = 0

	var path = "res://Textures/cards/black/"
	if not DirAccess.dir_exists_absolute(path):
		push_error("Card directory not found: " + path)
		return

	for file in DirAccess.get_files_at(path):
		if file.get_extension().to_lower() == "png":
			cards.append(file.get_basename())

	cards.shuffle()
	for file_name in cards:
		var card_node = card_scene.instantiate()
		add_child(card_node)
		card_node.set_card_file(file_name)
		card_node.hide()

		var rank = _rank_from_text(file_name)
		if rank == "":
			# A card script may know the value even if the filename is unusual.
			rank = _card_rank(card_node)

		if rank == "":
			push_error("Unknown card rank in file: " + file_name + ". Provide its filename format or card.gd.")
		else:
			card_node.set_meta("blackjack_rank", rank)

		shoe.append(card_node)

	shoe.shuffle()
	_audit_shoe_ranks()
	print("Shoe contains ", shoe.size(), " cards (no duplicates created).")


func _audit_shoe_ranks():
	# A standard single deck has four of each rank. Print the
	# distribution so incorrect card filenames are obvious.
	var counts = {}
	for card in shoe:
		var rank = _card_rank(card)
		counts[rank] = counts.get(rank, 0) + 1

	print("Shoe ranks: ", counts)
	if shoe.size() == 52:
		for rank in ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]:
			if counts.get(rank, 0) != 4:
				push_warning("Unexpected count for rank " + rank + ": " + str(counts.get(rank, 0)))


# --------------------------------------------------
# GAME SETUP
# --------------------------------------------------

func start_new_game():
	if Table == null:
		push_error("Assign the Table node in the Inspector first.")
		return

	if is_instance_valid(participants[dealerdemon]["Node"]):
		push_warning("The game has already been started.")
		return

	var available_positions = [
		Table.get_node("DemonSpawn2"),
		Table.get_node("DemonSpawn3"),
		Table.get_node("DemonSpawn4"),
		Table.get_node("DemonSpawn5")
	]

	var dealer_instance = dealerdemon.instantiate()
	add_child(dealer_instance)
	var dealer_pos = Table.get_node("DealerDemonSpawn")
	dealer_instance.global_position = dealer_pos.global_position
	participants[dealerdemon]["Node"] = dealer_instance
	participants[dealerdemon]["PositionNode"] = dealer_pos

	for demon in demonsNotPlaying.duplicate():
		var instance = demon.instantiate()
		add_child(instance)
		var random_pos = available_positions.pick_random()
		instance.global_position = random_pos.global_position
		available_positions.erase(random_pos)

		participants[demon]["Node"] = instance
		participants[demon]["PositionNode"] = random_pos
		demon_at_spawn[random_pos.name] = demon
		demonsPlaying.append(demon)

	demonsNotPlaying.clear()

	var player_instance = player.instantiate()
	add_child(player_instance)
	participants[player]["Node"] = player_instance
	participants[player]["PositionNode"] = Table.get_node("PlayerSpawn")
	player_instance.global_position = participants[player]["PositionNode"].get_child(0).global_position

	# This order ensures demons are judged BEFORE the player's turn.
	turnList = [
		demon_at_spawn["DemonSpawn4"],
		demon_at_spawn["DemonSpawn5"],
		demon_at_spawn["DemonSpawn3"],
		demon_at_spawn["DemonSpawn2"],
		dealerdemon,
		player
	]

	player_bust = false
	dealer_bust = false
	game_won = false
	print("Game started.")


# --------------------------------------------------
# ROUND START
# --------------------------------------------------

func new_round():
	if game_won or roundOngoing:
		return

	if not is_instance_valid(participants[player]["Node"]) or not is_instance_valid(participants[dealerdemon]["Node"]):
		push_error("Call start_new_game() before new_round().")
		return

	# Only recycle cards BETWEEN rounds (not mid-round).
	for participant in participants.keys():
		for card in participants[participant]["Cards"]:
			if is_instance_valid(card):
				card.hide()
				shoe.append(card)
		participants[participant]["Cards"] = []
		participants[participant]["value_of_cards"] = 0
		participants[participant]["TurnTaken"] = false

	for card in discarded_cards:
		if is_instance_valid(card):
			shoe.append(card)
	discarded_cards.clear()

	_clear_all_status_labels()
	player_bust = false
	dealer_bust = false
	npc_phase_complete = false
	npc_phase_running = false
	final_duel_round = demonsPlaying.size() == 1
	participants[player]["Node"].TurnTaken = false

	var required_cards = (demonsPlaying.size() + 1) * 2
	if shoe.size() < required_cards:
		print("Not enough cards to deal; rebuilding the shoe.")
		new_shoe()

	if shoe.size() < required_cards:
		push_error("Not enough cards to begin the round.")
		roundComplete = true
		return

	shoe.shuffle()
	roundComplete = false
	roundOngoing = true
	print("\n===== NEW ROUND =====")
	if final_duel_round:
		print("FINAL DUEL: PLAYER VS DEALER")

	for demon in demonsPlaying:
		var spawn = participants[demon]["PositionNode"].get_child(1) as Node3D
		if not deal_card(demon, spawn, 2, demon == dealerdemon):
			_abort_round("Initial demon deal failed.")
			return

	var player_spawn = participants[player]["PositionNode"].get_child(1) as Node3D
	if not deal_card(player, player_spawn, 2, false):
		_abort_round("Initial player deal failed.")
		return

	# A two-card 21 needs no further player input.
	if participants[player]["value_of_cards"] == 21:
		participants[player]["TurnTaken"] = true
		participants[player]["Node"].TurnTaken = true


# --------------------------------------------------
# CARD PLACEMENT
# --------------------------------------------------

func deal_card(participant, card_spawn: Node3D, quantity: int, new_round_dealer: bool) -> bool:
	if card_spawn == null or shoe.size() < quantity:
		return false

	var character = participants[participant]["Node"] as Node3D
	if character == null:
		return false

	var toward_character = character.global_position - card_spawn.global_position
	toward_character.y = 0.0
	if toward_character.length_squared() < 0.0001:
		push_error("Card spawn and character occupy the same horizontal position.")
		return false

	var right = toward_character.normalized().cross(Vector3.UP).normalized()

	for i in range(quantity):
		var card = shoe.pop_front()
		if card.get_parent() != self:
			card.reparent(self, true)

		var offset = (participants[participant]["Cards"].size() - 0.5) * 0.4
		if new_round_dealer:
			offset = (i - (quantity - 1) / 2.0) * 0.4

		card.global_position = card_spawn.global_position + right * offset
		var target = character.global_position
		target.y = card.global_position.y
		card.look_at(target, Vector3.UP, true)
		card.rotation_degrees.x = 90 if (new_round_dealer and i == 1) else -90
		card.show()
		participants[participant]["Cards"].append(card)

	if not calculate_hand_value(participant):
		return false

	_print_hand(participant)
	return true


# --------------------------------------------------
# VISIBLE NPC TURN FLOW
# Opponents -> dealer -> visible results -> player.
# This is ASYNCHRONOUS so a card stays on-screen between hits.
# --------------------------------------------------

func continue_round():
	if not roundOngoing or game_won:
		return

	# Do not accidentally start the NPC sequence again when the
	# player presses a button while demons are still playing.
	if npc_phase_running:
		return

	if not npc_phase_complete:
		npc_phase_running = true
		_play_npc_phase()
		return

	# Only reach player input AFTER all demon results are shown.
	if not participants[player]["TurnTaken"]:
		if not _take_player_turn():
			return

	if participants[player]["TurnTaken"]:
		_resolve_player_result()


# Compatibility with the previous manager API.
func hit_or_stand(_participant):
	continue_round()


func _play_npc_phase() -> void:
	print("----- DEMONS' TURNS -----")

	for participant in turnList:
		if not roundOngoing:
			npc_phase_running = false
			return
		if participant == player:
			break
		if not demonsPlaying.has(participant):
			continue

		if participant == dealerdemon:
			_reveal_dealer_hole_card()
			print("----- DEALER'S TURN -----")
		else:
			print("----- ", participants[participant]["Node"].name, "'S TURN -----")

		# Let the initial cards (or dealer's reveal) be seen.
		await get_tree().create_timer(npc_action_delay).timeout
		if not roundOngoing:
			npc_phase_running = false
			return

		while not participants[participant]["TurnTaken"] and roundOngoing:
			if not _take_npc_turn(participant):
				_abort_round("An NPC could not draw a card.")
				return

			# A card that was dealt must be rendered before the next hit
			# or the next demon starts. This was missing before.
			await get_tree().create_timer(npc_action_delay).timeout

	if not roundOngoing:
		npc_phase_running = false
		return

	# Dealers may bust. Display the result in world space and keep the dealer
	# present: a dealer only disappears if the player wins the final duel.
	dealer_bust = participants[dealerdemon]["value_of_cards"] > 21
	if dealer_bust and not status_labels.has(dealerdemon):
		_mark_npc_bust(dealerdemon)

	await _resolve_demon_results_visible()

	if not roundOngoing:
		npc_phase_running = false
		return

	npc_phase_complete = true
	npc_phase_running = false
	print("----- PLAYER'S TURN -----")

	# A natural 21 is already marked as a finished player turn.
	# Resolve it now, without requiring an extra click.
	if participants[player]["TurnTaken"]:
		_resolve_player_result()


func _reveal_dealer_hole_card():
	var dealer_cards = participants[dealerdemon]["Cards"]
	if dealer_cards.size() >= 2:
		dealer_cards[1].rotation_degrees.x = -90
		print("Dealer reveals the hidden card.")


func _take_npc_turn(participant) -> bool:
	var total = participants[participant]["value_of_cards"]

	if total > 21:
		_mark_npc_bust(participant)
		participants[participant]["TurnTaken"] = true
		return true

	if total == 21:
		participants[participant]["TurnTaken"] = true
		return true

	var wants_hit = false

	if participant == dealerdemon:
		# Dealer MUST draw on 16 or less. The next card can make
		# the dealer exceed 21: dealer bust is explicitly supported.
		# Stands on both hard 17 and soft 17.
		wants_hit = total < 17
	else:
		wants_hit = participants[participant]["Node"].hit_or_stand(total)

	if not wants_hit or shoe.is_empty():
		if shoe.is_empty() and wants_hit:
			print("Shoe empty: NPC must stand.")
		participants[participant]["TurnTaken"] = true
		return true

	var spawn = participants[participant]["PositionNode"].get_child(1) as Node3D
	if not deal_card(participant, spawn, 1, false):
		return false

	var new_total = participants[participant]["value_of_cards"]
	if new_total > 21:
		_mark_npc_bust(participant)
		participants[participant]["TurnTaken"] = true
	elif new_total == 21:
		participants[participant]["TurnTaken"] = true

	return true


func _mark_npc_bust(participant):
	if participant == dealerdemon:
		dealer_bust = true
		_show_status_label(participant, "DEALER BUST! (%d)" % participants[participant]["value_of_cards"], Color(1.0, 0.2, 0.2))
		print("DEALER BUST! Total: ", participants[participant]["value_of_cards"])
	else:
		_show_status_label(participant, "BUST! (%d)" % participants[participant]["value_of_cards"], Color(1.0, 0.2, 0.2))
		print(participants[participant]["Node"].name, " BUST! Total: ", participants[participant]["value_of_cards"])


func _show_status_label(participant, message: String, color: Color) -> void:
	_remove_status_label(participant)

	var character = participants[participant]["Node"] as Node3D
	if not is_instance_valid(character):
		return

	# Label3D is a real 3D object, not a screen-space label.
	# Parenting it to the character automatically follows movements.
	var label = Label3D.new()
	label.name = "Status3D_" + character.name
	label.text = message
	label.font_size = status_label_font_size
	label.pixel_size = status_label_pixel_size
	label.modulate = color
	label.outline_modulate = Color(0, 0, 0, 1)
	label.outline_size = 10
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.shaded = false
	label.no_depth_test = true
	label.double_sided = true
	label.fixed_size = false

	# The full-screen shader writes ALPHA, so it draws in the transparent pass.
	# These priorities put Label3D above the full-screen pass when the
	# post-process material uses its normal priority of 0.
	label.render_priority = 127
	label.outline_render_priority = 126

	character.add_child(label)
	label.global_position = character.global_position + Vector3.UP * result_label_height
	status_labels[participant] = label


func _remove_status_label(participant) -> void:
	if not status_labels.has(participant):
		return
	var label: Label3D = status_labels[participant]
	status_labels.erase(participant)
	if is_instance_valid(label):
		label.queue_free()


func _clear_all_status_labels() -> void:
	for participant in status_labels.keys():
		_remove_status_label(participant)


func _take_player_turn() -> bool:
	var player_node = participants[player]["Node"]
	var wants_hit = player_node.hit_or_stand()

	if wants_hit == true and not player_node.TurnTaken:
		if shoe.is_empty():
			print("Shoe empty: player must stand.")
			player_node.TurnTaken = true
		else:
			var spawn = participants[player]["PositionNode"].get_child(1) as Node3D
			if not deal_card(player, spawn, 1, false):
				_abort_round("Player draw failed; check card ranks and spawn.")
				return false

			var total = participants[player]["value_of_cards"]
			if total > 21:
				player_bust = true
				player_node.TurnTaken = true
				print("PLAYER BUST!")
			elif total == 21:
				player_node.TurnTaken = true

	participants[player]["TurnTaken"] = player_node.TurnTaken
	return participants[player]["TurnTaken"]


# --------------------------------------------------
# DEMONS: SHOW RESULT FIRST, THEN REMOVE LOSERS
# --------------------------------------------------

func _resolve_demon_results_visible() -> void:
	var dealer_total = participants[dealerdemon]["value_of_cards"]
	var dealer_blackjack = _is_blackjack(dealerdemon)

	print("----- DEMONS VS DEALER (", dealer_total, ") -----")

	for demon in demonsPlaying.duplicate():
		if demon == dealerdemon:
			continue

		var demon_total = participants[demon]["value_of_cards"]
		var demon_blackjack = _is_blackjack(demon)
		var demon_busted = demon_total > 21
		var lost = demon_busted

		if not demon_busted and not dealer_bust:
			lost = demon_total < dealer_total
			if demon_total == dealer_total and dealer_blackjack and not demon_blackjack:
				lost = true

		var demon_node = participants[demon]["Node"]
		if lost:
			if demon_busted:
				_show_status_label(demon, "BUST! (%d)" % demon_total, Color(1.0, 0.2, 0.2))
			else:
				_show_status_label(demon, "LOST! (%d vs %d)" % [demon_total, dealer_total], Color(1.0, 0.2, 0.2))
			print(demon_node.name, " LOSES (", demon_total, " vs ", dealer_total, ")")

			# Do not delete the character and cards in the same frame.
			# Give the player time to see the final hand and label.
			await get_tree().create_timer(result_display_delay).timeout
			if not roundOngoing:
				return

			# Use the existing death() method if that demon has one.
			# Wait after calling it so a death animation may play.
			if play_demon_death_animation and is_instance_valid(demon_node) and demon_node.has_method("death"):
				demon_node.death()
				if death_animation_delay > 0.0:
					await get_tree().create_timer(death_animation_delay).timeout
					if not roundOngoing:
						return

			remove_losing_demon(demon)
		else:
			# Survivors remain in the scene with their cards showing.
			print(demon_node.name, " SURVIVES (", demon_total, " vs ", dealer_total, ")")


func remove_losing_demon(demon):
	if demon == player or demon == dealerdemon or not demonsPlaying.has(demon):
		return

	var demon_node = participants[demon]["Node"]

	# These cards have already been seen this round.
	# Do NOT make them available for the player to draw now.
	for card in participants[demon]["Cards"]:
		if is_instance_valid(card):
			card.hide()
			discarded_cards.append(card)

	participants[demon]["Cards"] = []
	participants[demon]["value_of_cards"] = 0
	participants[demon]["TurnTaken"] = true

	demonsPlaying.erase(demon)
	turnList.erase(demon)

	var position_node = participants[demon]["PositionNode"]
	if position_node != null:
		demon_at_spawn.erase(position_node.name)

	participants[demon]["PositionNode"] = null
	participants[demon]["Node"] = null

	_remove_status_label(demon)
	if is_instance_valid(demon_node):
		demon_node.queue_free()


# --------------------------------------------------
# PLAYER VS DEALER
# --------------------------------------------------

func _resolve_player_result():
	if not roundOngoing:
		return

	roundOngoing = false
	roundComplete = true

	var player_total = participants[player]["value_of_cards"]
	var dealer_total = participants[dealerdemon]["value_of_cards"]

	print("----- PLAYER VS DEALER -----")
	print("Player: ", player_total, " | Dealer: ", dealer_total)

	if player_bust or player_total > 21:
		player_bust = true
		print("PLAYER BUST! Player loses the round.")
		return

	var player_blackjack = _is_blackjack(player)
	var dealer_blackjack = _is_blackjack(dealerdemon)

	var player_wins = dealer_total > 21 or player_total > dealer_total
	if player_total == dealer_total and player_blackjack and not dealer_blackjack:
		player_wins = true

	if player_wins:
		print("PLAYER WINS THIS ROUND!")
		if final_duel_round:
			win_game()
		else:
			print("Player advances. Preparing the next round.")
			new_round()
			# Continue new round automatically, without requiring an
			# unrelated user click to start the NPC sequence.
			if roundOngoing:
				call_deferred("continue_round")
		return

	if player_total == dealer_total and player_blackjack == dealer_blackjack:
		print("PUSH (TIE). Player does not advance.")
	else:
		print("PLAYER LOSES TO DEALER.")


func win_game():
	if game_won:
		return

	game_won = true
	roundOngoing = false
	roundComplete = true
	_clear_all_status_labels()

	print("PLAYER WON THE FINAL ONE-ON-ONE DEALER ROUND!")
	print("GAME WON! DEALER REMOVED!")

	var dealer_node = participants[dealerdemon]["Node"]
	if is_instance_valid(dealer_node):
		dealer_node.queue_free()

	participants[dealerdemon]["Node"] = null
	demonsPlaying.erase(dealerdemon)
	turnList.erase(dealerdemon)


func _abort_round(reason: String):
	push_error(reason)
	roundOngoing = false
	roundComplete = true
	npc_phase_running = false
	print("Round stopped due to an error; no results applied.")
