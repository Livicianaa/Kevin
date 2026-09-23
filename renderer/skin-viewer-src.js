import { SkinViewer } from 'skinview3d';
import { KevinAnimator, ANIMATION_STATES } from './animations.js';

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

  return viewer;
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

function setSpeed(value) {
  if (animator) animator.speed = value;
}

function currentState() {
  return animator ? animator.state : null;
}

window.KevinSkin = { initSkinViewer, setState, play, setSitting, setSpeed, currentState, ANIMATION_STATES };
