import { SkinViewer, IdleAnimation } from 'skinview3d';

let viewer = null;

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
  viewer.camera.position.set(0, 0, 60);
  viewer.fov = 30;
  viewer.zoom = 0.95;
  viewer.animation = new IdleAnimation();

  return viewer;
}

window.KevinSkin = { initSkinViewer };
