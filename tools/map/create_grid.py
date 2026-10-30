from PIL import Image, ImageDraw, ImageFont

img = Image.open('tools/map/esri_northwest.jpg')
w, h = img.size

# Draw grid lines every 50 pixels and labels every 100 pixels
draw_img = img.copy()
draw = ImageDraw.Draw(draw_img)

for x in range(0, w, 50):
    col = (255, 255, 0) if x % 100 == 0 else (100, 100, 100)
    draw.line([(x, 0), (x, h)], fill=col, width=1 if x % 100 != 0 else 2)
    if x % 100 == 0:
        draw.text((x + 2, 10), str(x), fill=(255, 255, 0))

for y in range(0, h, 50):
    col = (255, 255, 0) if y % 100 == 0 else (100, 100, 100)
    draw.line([(0, y), (w, y)], fill=col, width=1 if y % 100 != 0 else 2)
    if y % 100 == 0:
        draw.text((10, y + 2), str(y), fill=(255, 255, 0))

draw_img.save('tools/map/esri_grid.jpg')
print("Saved tools/map/esri_grid.jpg with 50px/100px grid")
