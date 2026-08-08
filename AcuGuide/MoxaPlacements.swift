import Foundation

// THE PLACEMENT CARDS — the moxa tab's entry point.
//
// WHY PLACEMENTS AND NOT CONCERNS. The obvious build is a symptom menu: pick what is bothering you,
// get told where to put the box. That is a prescription, and it is the one thing this app does not
// do. It turns out not to be a compromise, because the tradition's own groupings and the box's
// physical footprint COINCIDE — the classical points fall into exactly three box placements. So the
// cards can route on WHERE ON THE BODY and lose nothing: a user asking "where does this go" is
// answered directly, and no symptom is ever collected or matched.
//
// The routing question therefore asks what the user can DO right now — lie flat, sit, or has someone
// to help — because that is the real constraint. One placement is unreachable alone, one needs bare
// abdomen and a flat surface, one is done sitting. It reads as practical rather than clinical, which
// it is.
//
// WHAT IS DELIBERATELY NOT HERE. No sequence claim. The draft cited 先上后下 ("upper before lower")
// to justify presenting these in A→B→C order, but the rule as written is 先阳后阴……先上后下 — yang
// before yin puts the BACK before the front, i.e. B→A→C. Half-quoting a real source to authorise
// the app's own ordering is worse than having no ordering, so the cards claim nothing about order.
struct MoxaPlacement: Identifiable {
    let id: String
    let titleZh: String, titleEn: String
    let bodyZh: String, bodyEn: String
    /// Points from `MoxaAtlas` this placement covers.
    let moxaPointIds: [String]
    /// Points already in the ungated `Acupoint.all` that belong to the same region — referenced by
    /// name rather than duplicated, so there is one source of truth per point.
    let atlasPointIds: [String]

    var title: String { AppLocale.pick(titleZh, titleEn) }
    var body: String { AppLocale.pick(bodyZh, bodyEn) }
    var points: [MoxaPoint] { moxaPointIds.compactMap { id in MoxaAtlas.all.first { $0.id == id } } }
}

enum MoxaPlacements {
    /// Asks what the user can do, not what is wrong with them. "What is bothering you?" invites a
    /// symptom and makes the next screen a prescription; this collects nothing about the body and is
    /// answerable in a second.
    static var routingQuestion: String {
        AppLocale.pick(
            "现在方便平躺、方便坐着，还是有人能搭把手？下面三处是身体上的三个位置，不是三种不同的用途。哪一处都可以看；这个问题只关乎你眼下能做到哪一处。",
            "Right now — can you lie flat, are you sitting, or is there someone here who can help? The three placements below are three places on the body, not three different purposes. Any of them can be read; the question is only which one you are in a position to do.")
    }

    static let all: [MoxaPlacement] = [
        MoxaPlacement(
            id: "abdomen-midline",
            titleZh: "腹部中线（平躺着自己量）",
            titleEn: "The abdominal midline — measured lying flat",
            bodyZh: """
            从肚脐量到耻骨上缘是一段骨度：GB/T 12346—2021 与 WHO 2008 都定为5寸——不论你自己量出来是多长，都分成同样多的份数，所以从头到尾用不到任何厘米数。标出这两处，神阙、气海、关元就都定下来了，分别在这一段的 0.00、0.30、0.60 处。量的时候要平躺，并先排空膀胱：膀胱充盈会鼓过耻骨上缘，把你所依据的那个骨性标志盖住。

            三处同在任脉前正中线上，一个在另一个下方，所以艾灸盒在这里盖住的是这条线上的一段，而不是某一个点。石门（CV5）就在气海与关元之间，一个盒子无法既罩住这两处又避开它；古籍对石门有专门针对有生育打算的女性的告诫，若你在意这一条，就一次只对准一个穴位。

            把这三处放在一起的，是这一段骨度和它们共处的这条正中线——是位置上的关系，不是关于它们的任何说法。

            中脘不在这一段里：它属于上一段骨度（胸剑联合中点，也就是肋骨在胸骨下端交汇处，到脐中，8寸），要另外量；它和天枢已经在本应用的主穴位图里。
            """,
            bodyEn: """
            Navel to the top edge of the pubic bone is one proportional span: GB/T 12346—2021 and WHO 2008 both fix it at 5 cun, divided into the same number of parts whatever your own body measures, so no centimetre figure is ever needed. Mark those two places and Shenque, Qihai and Guanyuan are all placed — 0.00, 0.30 and 0.60 along the span. Measure it lying flat with an empty bladder: a full bladder rises above the pubic border and pads the landmark you are measuring from.

            All three sit on the Ren vessel along the front midline, one below the next, so a box here covers a stretch of that line rather than a single spot. Shimen CV5 lies between Qihai and Guanyuan, so no single box covers both of them and stays off it; the classical texts single Shimen out for women who may want to conceive, and if that matters to you, place the box for one point at a time.

            What groups these three is the span and the midline they share — where they sit, not what is said about them.

            Zhongwan is not on this span. It belongs to the upper one — the xiphisternal junction, where the ribs meet below the breastbone, down to the navel, 8 cun — and has to be measured separately; it and Tianshu are already in the app's main point atlas.
            """,
            moxaPointIds: ["CV8", "CV6", "CV4"],
            atlasPointIds: ["CV12", "ST25"]),

        MoxaPlacement(
            id: "lumbar-l2",
            titleZh: "第2腰椎一线上的三处——在背后，需要别人帮忙",
            titleEn: "Three places on one vertebra (L2) — on the back, needs a second person",
            bodyZh: """
            这一处自己看不到、也够不着。需要另一个人放置艾灸盒，并按时查看皮肤；需要计时；绑带式的盒子不要躺着用——绑上以后取不下来，而这正是这样一个够不着的位置最糟的情况。肾俞左右成对，受热皮肤面积加倍，盒子放偏就可能只烫到一侧，所以每次两侧都要查。

            三处的位置：命门在后正中线上、第2腰椎棘突下的凹陷里；两侧肾俞与它同高，各旁开1.5寸——三处在同一条横线上。（GB/T 12346—2021；WHO 2008 同）古籍也把它们记在同一椎：《针灸甲乙经·卷三》命门在「十四椎节下间」，肾俞在「第十四椎下，两傍各一寸五分」。

            盒子够不够得着这三处，是个算术问题，不是去换更大盒子的理由。宽的多孔腰盒（10厘米以上）以后正中线为中心放置，可同时覆盖三处；常见的5–6厘米单孔小盒够不到旁开约4厘米的两侧，只能对准中间的命门。覆盖的地方多，不等于更多的热、更长的时间——盒子宽只是宽而已。两侧若分开做，每一次都是一次单独的施灸，各自计时，而且是在自己看不见的皮肤上。

            靠摸髂嵴来定第2腰椎，通常会偏高约一节、有时两节，女性更明显——所以这里给的是一个范围，不是一个点。
            """,
            bodyEn: """
            This is the one placement you can neither see nor reach. It needs a second person to put the box down and to look at the skin at set intervals; it needs a timer; and never use a strap-on box lying down — once strapped it cannot be got off quickly, which is the worst failure mode for a spot that is already out of reach. Being a pair, Shenshu also puts twice the skin area under heat, and a box that sits unevenly can burn one side only, so check both sides every time.

            Where the three sit: Mingmen is on the back midline, in the hollow just below the L2 spinous process, and the two Shenshu points are level with it, 1.5 cun out on either side — three places on one horizontal line. (GB/T 12346—2021; WHO 2008.) The old texts put them at the same vertebra too: 《针灸甲乙经》 vol. 3 records Mingmen below the 14th vertebra and Shenshu below the 14th vertebra, 1.5 cun either side.

            Whether your box reaches all three is arithmetic, not a reason to go and get a bigger one. A wide multi-hole lumbar box, 10 cm or more across, centred on the posterior midline sits over all three at once; a common 5–6 cm single-hole box does not reach the pair about 4 cm out, so it goes on Mingmen alone. Covering more places is not more heat and not more time — a wider box is only wider. If the two sides are done separately, each turn is its own separate application, timed on its own, on skin you cannot see.

            Finding L2 by feeling for the hip bones lands about one level high, sometimes two, and more often so in women — so this one is given as an area rather than a dot.
            """,
            moxaPointIds: ["GV4", "BL23"],
            atlasPointIds: []),

        MoxaPlacement(
            id: "shins-st36",
            titleZh: "小腿外侧的足三里（坐着做）",
            titleEn: "Zusanli on the shins — done sitting",
            bodyZh: """
            坐在椅子上，膝盖屈起，双脚平放。这一处左右各一，自己看得见、也够得着，皮肤随时能查——这是三处里唯一具备这三点的。

            足三里已经在本应用的主穴位图里，找法也在那里：犊鼻（ST35）下3寸，胫骨前嵴外开一横指。请以那一页为准，这里不另写一份。

            小腿是三处里唯一一个倾斜、有弧度、又没有软垫的表面，所以盒子会往下滑。放好之后先看着它待一会儿，再把注意力挪开；用绑带的话，绑在小腿上，不要绑在膝盖上。

            古籍里关于施灸顺序有一句常被引用的话，值得完整地看：《千金要方》讲的是「先阳后阴……先上后下」——先阳后阴的意思是背面在腹面之前。所以那句话并不支持「腹—腰—腿」这个顺序；本应用对顺序不作任何主张。
            """,
            bodyEn: """
            Sit on a chair with your knees bent and your feet flat. There is one on each leg, and this is the only placement of the three you can see, reach, and check the skin on at any moment.

            Zusanli is already in the app's main point atlas, and so is how to find it: 3 cun below Dubi ST35, one finger-breadth out from the front crest of the shin bone. Use that page rather than a second copy of it here.

            The shin is the only one of the three placements on a sloped, curved, unpadded surface, so a box will slide. Watch it for a moment after you set it down before your attention goes elsewhere, and if you strap it, strap it to the calf and not across the knee.

            There is a line about the order of a session that gets quoted often, and it is worth reading whole: 《千金要方》 says 先阳后阴……先上后下 — yang before yin, which puts the back before the front. So it does not support an abdomen-then-back-then-legs order, and this app makes no claim about sequence.
            """,
            moxaPointIds: [],
            atlasPointIds: ["ST36"]),
    ]
}
