"""Original wood frame and cloth straps; follows the 12x12 ArtSpec.ITEM contract."""
from PIL import Image, ImageDraw
im = Image.new('RGBA', (12, 12)); d = ImageDraw.Draw(im)
d.rectangle((2, 0, 3, 11), fill='#664c36'); d.rectangle((8, 0, 9, 11), fill='#664c36')
for y in (1, 6, 10): d.rectangle((3,y,8,y+1),fill='#b99b69')
d.rectangle((4,3,7,9),fill='#658278'); d.rectangle((5,4,6,8),fill='#adc0a0')
d.line((2,1,2,10),fill='#e0c28a'); d.line((9,1,9,10),fill='#e0c28a')
im.save('assets/resources/item_haul_frame.png')
