$ErrorActionPreference = "Stop"

# 标准用户复跑支持：GODOT_EXE 环境变量覆盖 godot 路径（tester 无 PATH 链接）
if ($env:GODOT_EXE) { $godotBin = $env:GODOT_EXE } else { $godotBin = "godot" }

# v1.37 整改02：超时按场景设置——默认 1200 帧；专项（反馈全流程约 25s）单独 2000 帧。
# 正常 PASS 后测试立即 quit(0)，超时只影响"未完成"场景，不增加已通过场景耗时。
$sceneTimeouts = @{
    "res://tests/test_combat_feedback_sequence_scene.tscn" = "2000"
    "res://tests/test_feedback_lifecycle_main_scene.tscn" = "2000"
    "res://tests/test_save_integrity_scene.tscn" = "2000"
    "res://tests/test_doc_revoked_scene.tscn" = "600"
    "res://tests/test_story_dialogue_state_machine_scene.tscn" = "2000"
}
$defaultTimeout = "1200"

$scenes = @(
    "res://tests/test_inventory_scene.tscn",
    "res://tests/test_combat_scene.tscn",
    "res://tests/test_mining_scene.tscn",
    "res://tests/test_fuwa_scene.tscn",
    "res://tests/test_garden_lottery_scene.tscn",
    "res://tests/test_persistent_health_scene.tscn",
    "res://tests/test_scene_battle_scene.tscn",
    "res://tests/test_monster_tooltip_scene.tscn",
    "res://tests/test_monster_attack_animation_scene.tscn",
    "res://tests/test_monster_hit_scene.tscn",
    "res://tests/test_player_native_motion_scene.tscn",
    "res://tests/test_pet_combination_scene.tscn",
    "res://tests/test_native_footer_scene.tscn",
    "res://tests/test_native_map_exits_scene.tscn",
    "res://tests/test_native_storage_scene.tscn",
    "res://tests/test_native_shop_scene.tscn",
    "res://tests/test_native_dialogue_scene.tscn",
    "res://tests/test_native_equipment_scene.tscn",
    "res://tests/test_native_pet_bag_scene.tscn",
    "res://tests/test_native_skill_panel_scene.tscn",
    "res://tests/test_native_enhancement_panel_scene.tscn",
    "res://tests/test_progression_flow_panel_scene.tscn",
    "res://tests/test_native_research_flow_scene.tscn",
    "res://tests/test_quest_flow_guide_scene.tscn",
    "res://tests/test_complete_game_flow_scene.tscn",
    "res://tests/test_daily_officer_scene.tscn",
    "res://tests/test_palace_scene.tscn",
    "res://tests/test_pk_tournament_scene.tscn",
    "res://tests/test_war_soul_maze_scene.tscn",
    "res://tests/test_story_scene.tscn",
    "res://tests/test_final_campaign_scene.tscn",
    "res://tests/test_ending_scene.tscn",
    "res://tests/test_territory_scene.tscn",
    "res://tests/test_world_equipment_battle_scene.tscn",
    "res://tests/test_world_population_scene.tscn",
    "res://tests/test_city_npc_scene.tscn",
    "res://tests/test_native_loot_scene.tscn",
    "res://tests/test_pet_scene.tscn",
    "res://tests/test_pet_ui_scene.tscn",
    "res://tests/test_progression_scene.tscn",
    "res://tests/test_relationship_scene.tscn",
    "res://tests/test_quest_scene.tscn",
    "res://tests/test_skill_scene.tscn",
    "res://tests/test_main_scene.tscn",
    "res://tests/test_original_ui_scene.tscn",
    "res://tests/test_enhancement_scene.tscn",
    "res://tests/test_swf_evidence_registry_scene.tscn",
    "res://tests/test_no_legacy_panels_scene.tscn",
    "res://tests/test_native_npc_progression_routes_scene.tscn",
    "res://tests/test_world_interaction_registry_scene.tscn",
    "res://tests/test_native_timeline_registry_scene.tscn",
    "res://tests/test_combat_feedback_sequence_scene.tscn",
    "res://tests/test_feedback_lifecycle_main_scene.tscn",
    "res://tests/test_doc_revoked_scene.tscn",
    "res://tests/test_story_dialogue_state_machine_scene.tscn",
    "res://tests/ui_audit/test_ui_startup_panels_hidden_scene.tscn",
    "res://tests/ui_audit/test_ui_hud_layout_audit_scene.tscn",
    "res://tests/ui_audit/test_ui_player_movement_scene.tscn",
    "res://tests/ui_audit/test_ui_map_exit_blocking_scene.tscn",
    "res://tests/ui_audit/test_ui_status_prompt_layer_scene.tscn",
    "res://tests/ui_audit/test_ui_panel_bounds_scene.tscn",
    "res://tests/test_value_audit_registry_scene.tscn",
    "res://tests/test_save_integrity_scene.tscn",
    "res://tests/test_release_candidate_scene.tscn",
    "res://tests/test_release_acceptance_scene.tscn"
)

foreach ($scene in $scenes) {
    Write-Host "RUN $scene"
    $quitAfter = if ($sceneTimeouts.ContainsKey($scene)) { $sceneTimeouts[$scene] } else { $defaultTimeout }
    $logFile = Join-Path $env:TEMP ("godot-remake-" + [Guid]::NewGuid().ToString("N") + ".log")
    $process = Start-Process -FilePath $godotBin -ArgumentList @(
        "--headless",
        "--path", $PSScriptRoot,
        "--scene", $scene,
        "--quit-after", $quitAfter,
        "--log-file", $logFile
    ) -WindowStyle Hidden -Wait -PassThru
    $scriptErrors = Select-String -LiteralPath $logFile -Pattern "SCRIPT ERROR:|^ERROR:" -ErrorAction SilentlyContinue | Where-Object { $_.Line -notmatch "Failed to read the root certificate store" }
    # P2 拒签整改：ObjectDB 泄漏计入非洁净（不得只查 SCRIPT ERROR/^ERROR）
    $leakMarks = @(Select-String -LiteralPath $logFile -Pattern "ObjectDB instances leaked" -ErrorAction SilentlyContinue)
    $passMarks = @(Select-String -LiteralPath $logFile -Pattern "^PASS " -ErrorAction SilentlyContinue)
    # P0-3：显式识别 SKIP/SKIPPED/TEST_USER_DATA_NOT_WRITABLE 并判失败
    $skipMarks = @(Select-String -LiteralPath $logFile -Pattern "SKIP|SKIPPED|TEST_USER_DATA_NOT_WRITABLE" -ErrorAction SilentlyContinue)
    if ($skipMarks.Count -gt 0) {
        Write-Error "FAILED $scene (SKIP/NOT_WRITABLE detected; see log: $logFile)"
        exit 1
    }
    if ($process.ExitCode -ne 0 -or $scriptErrors -or $leakMarks.Count -gt 0 -or $passMarks.Count -eq 0) {
        if ($scriptErrors) {
            Write-Error "FAILED $scene (script errors; see log: $logFile)"
        } elseif ($leakMarks.Count -gt 0) {
            Write-Error "FAILED $scene (ObjectDB instances leaked at exit; see log: $logFile)"
        } elseif ($process.ExitCode -ne 0) {
            Write-Error "FAILED $scene (exit $($process.ExitCode); see log: $logFile)"
        } else {
            Write-Error "FAILED $scene (no PASS completion marker before --quit-after; see log: $logFile)"
        }
        exit 1
    }
    Remove-Item -LiteralPath $logFile -Force -ErrorAction SilentlyContinue
}

Write-Host "RUN main scene smoke test"
$smokeLog = Join-Path $env:TEMP ("godot-remake-smoke-" + [Guid]::NewGuid().ToString("N") + ".log")
$smoke = Start-Process -FilePath $godotBin -ArgumentList @(
    "--headless",
    "--path", $PSScriptRoot,
    "--quit-after", "300",
    "--log-file", $smokeLog
) -WindowStyle Hidden -Wait -PassThru
$smokeErrors = Select-String -LiteralPath $smokeLog -Pattern "SCRIPT ERROR:|^ERROR:" -ErrorAction SilentlyContinue | Where-Object { $_.Line -notmatch "Failed to read the root certificate store" }
$smokeLeaks = @(Select-String -LiteralPath $smokeLog -Pattern "ObjectDB instances leaked" -ErrorAction SilentlyContinue)
if ($smoke.ExitCode -ne 0 -or $smokeErrors -or $smokeLeaks.Count -gt 0) {
    Write-Error "FAILED main scene smoke test (exit $($smoke.ExitCode); see log: $smokeLog)"
    exit 1
}
Remove-Item -LiteralPath $smokeLog -Force -ErrorAction SilentlyContinue

Write-Host "PASS all automated scenes and main smoke test"
exit 0




