import { SkinViewer } from 'skinview3d';
import { KevinAnimator, ANIMATION_STATES } from './animations.js';
import { KevinWorld } from './world.js';
import { loadCem } from './cem.js';

let viewer = null;
let animator = null;

function initSkinViewer(canvas, skinUrl, width, height) {
  if (viewer) {
    viewer.dispose();
  }

  viewer = new SkinViewer({
    canvas,
    width,
    height,
    skin: skinUrl,
  });

  viewer.background = null;
  viewer.fov = 30;
  viewer.zoom = 0.68;
  viewer.playerWrapper.position.y = 1;

  animator = new KevinAnimator();
  viewer.animation = animator;

  // skinview3d kendi rAF dongusunde monitorun hizinda (180 Hz) render ediyordu.
  // Kapatip tek bir 60 FPS dongusunden surduruyoruz.
  viewer.renderPaused = true;

  return viewer;
}

function tick(dt) {
  if (!viewer || !animator) return;
  animator.update(viewer.playerObject, dt);
  viewer.render();
}

function setState(name) {
  if (animator) animator.setState(name);
}

function play(name) {
  if (animator) animator.play(name);
}

function setSitting(value) {
  if (animator) animator.setSitting(value);
}

function useCemPack(jemText) {
  if (!animator) return { ok: false, reason: 'animator hazir degil' };
  try {
    const cem = loadCem(jemText);
    animator.setCemAnimator(cem);
    return { ok: true, assignments: cem.assignments.length, warnings: cem.warnings };
  } catch (err) {
    return { ok: false, reason: err.message };
  }
}

function setCemContext(context) {
  if (animator) animator.setCemContext(context);
}

function setLook(yaw, pitch) {
  if (animator) animator.setLook(yaw, pitch);
}

function setRootRotation(z) {
  if (animator) animator.setRootRotation(z);
}

function setFacing(radians) {
  if (animator) animator.setFacing(radians);
}

function setSpeed(value) {
  if (animator) animator.speed = value;
}

function currentState() {
  return animator ? animator.state : null;
}

window.KevinWorld = KevinWorld;
window.KevinSkin = { initSkinViewer, tick, setState, play, setSitting, setFacing, setLook, setRootRotation, setSpeed, useCemPack, setCemContext, currentState, ANIMATION_STATES };
