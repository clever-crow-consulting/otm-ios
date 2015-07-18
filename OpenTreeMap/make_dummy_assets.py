

of = open("./make_dummy_assets.sh","w")
pngs = open("./png_list.txt").readlines()
for png in pngs:
    of.write("cp ./Icon.png ./skin/images/" + png)
