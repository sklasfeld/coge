/*-----------------------------------------------------------------------------------------------------------------
 ~~~~SELECTABLE OPTIONS~~~~
 -----------------------------------------------------------------------------------------------------------------*/

var knKsSelect; // "Ks" or "Kn"
var comparisonSelect; // "mean", "xy", "xz", or "yz"
var colorSelect; // "Jet", "Bluered", "Portland", or "Viridis"

var camView = { "x": 0, "y": 0, "z": 30 };
var pointData = [];
/*-----------------------------------------------------------------------------------------------------------------
 ~~~~CORE FUNCTION DEFINITIONS~~~~
 + loadData(xID, yID, zID, xyjson, xzjson, mergejson, histo)
 + renderHistogram(documentElement, histogramTitle, histogramData, binCount)
 + renderSynMap(xChr, yChr, zChr, matches, histogram_data)
 -----------------------------------------------------------------------------------------------------------------*/

/* CORE FUNCTION: Load Data */
function loadData(xID, yID, zID, xyjson, xzjson, mergejson, histo) {
    // TODO: Combine XY and XZ genome/chromosome info into one file (faster loading) - generate w/ three_dots_merge.py
    var xChr,
        yChr,
        zChr,
        matches,
        histogram_data;

    function loadXY() {
        return $.ajax({
                       type: 'GET',
                       url: xyjson,
                       dataType: 'json',
                       success: function(data) {
                           xChr = data["genomes"][xID]["chromosomes"];
                           yChr = data["genomes"][yID]["chromosomes"];
                       },
                       error: function(xhr, status, error) {
                           console.warn("XY JSON Error: " + error);
                       }
                     })
    }

    function loadXZ() {
        return $.ajax({
                       type: 'GET',
                       url: xzjson,
                       dataType: 'json',
                       success: function(data) {
                           zChr = data["genomes"][zID]["chromosomes"];
                       },
                       error: function(xhr, status, error) {
                           console.warn("XZ JSON Error: " + error);
                       }
                     })
    }

    function loadThree() {
        return $.ajax({
                       type: 'GET',
                       url: mergejson,
                       dataType: 'json',
                       success: function(data) {
                           matches = data;
                       },
                       error: function(xhr, status, error) {
                           console.warn("Threeway JSON Error: " + error);
                       }
                     })
    }

    function loadHistogram() {
        return $.ajax({
                       type: 'GET',
                       url: histo,
                       dataType: 'json',
                       success: function(data) {
                           histogram_data = data;
                       },
                       error: function(xhr, status, error) {
                           console.log("Histogram JSON Error: " + error);
                       }
                     })
    }

    return $.when( loadXY(), loadXZ(), loadThree(), loadHistogram())
        .then( function() {
            return { "xChr": xChr, "yChr": yChr, "zChr": zChr, "matches": matches, "histogram_data": histogram_data };
        });
}

/* CORE FUNCTION: Render Histogram */
function renderHistogram(documentElement, histogramTitle, histogramData, binCount) {
    //TODO: Alternate between visualizations using arrows
    //i.e. http://jsfiddle.net/jtbowden/ykbgT/2/

    // Assign array to store number of bins requested
    var colorArray = [];
    for (var i = 0; i < binCount; i++) {
        colorArray.push(i);
    }
    // Store maximum and minimum values
    var minVal = Math.min.apply(null, histogramData);
    var maxVal = Math.max.apply(null, histogramData);

    // Plotly data object
    var data = [
        {
            x: histogramData,
            marker: {
                cmax: binCount,
                cmin: 0,
                color: colorArray,
                colorscale: colorSelect //'Jet' //'Bluered' //'Portland' //'Viridis'
            },
            type: 'histogram',
            xbins: {
                start: minVal,
                end: maxVal,
                size: (maxVal - minVal) / binCount
            }
        }
    ];

    // Plotly layout object
    var layout = {
        title: histogramTitle,
        xaxis: {fixedrange: true},
        yaxis: {title: 'Count', fixedrange: true}
    };

    // Render with Plotly
    Plotly.newPlot(documentElement, data, layout, {showLink: false, displayModeBar: false});
}

/* CORE FUNCTION: Render SynMap */
//TODO: Scale dynamically & position camera based on size
//TODO: Render selected point into a new info pane
//TODO: Launch GEvo from info pane
function renderSynMap(xChr, yChr, zChr, matches, histogram_data) {
    /*---------------------------------------------------------------------------------------------------------
     ~~~~VARIABLE DECLARATIONS~~~~
     --------------------------------------------------------------------------------------------------------*/

    // Rendering Variables
    var renderer, scene, camera, controls;
    var container = document.getElementById("canvas");
    var width, height, containerWidth, containerHeight;

    // Visualization & Data variables.
    var startPositions = {"x": 0, "y": 0, "z": 0};
    var points;
    var xAxis, yAxis, zAxis;
    var xChrIndexed, yChrIndexed, zChrIndexed;
    var grid;

    // Scaling variables.
    var scaleFactor = 0.00000001;
    var axisWidth = 0.05;
    var POINT_SIZE = 10;

    // Raycasting variables.
    var raycaster, intersects;
    var mouse, INTERSECTED;
    var ptHistory = ["NULL", "NULL"];
    var black = new THREE.Color("#000");

    // TODO: Pull these straight from Plotly
    // https://github.com/plotly/plotly.js/blob/master/src/components/colorscale/scales.js
    var schemes = {
        "Jet": [[0,'rgb(0,0,131)'], [0.125,'rgb(0,60,170)'], [0.375,'rgb(5,255,255)'],
            [0.625,'rgb(255,255,0)'], [0.875,'rgb(250,0,0)'], [1,'rgb(128,0,0)']],

        "Bluered": [[0,'rgb(0,0,255)'],[1,'rgb(255,0,0)']],

        "Portland": [[0,'rgb(12,51,131)'],[0.25,'rgb(10,136,186)'], [0.5,'rgb(242,211,56)'],
            [0.75,'rgb(242,143,56)'], [1,'rgb(217,30,30)']],

        "Viridis": [[0,'#440154'],[0.06274509803921569,'#48186a'], [0.12549019607843137,'#472d7b'],
            [0.18823529411764706,'#424086'], [0.25098039215686274,'#3b528b'],[0.3137254901960784,'#33638d'],
            [0.3764705882352941,'#2c728e'], [0.4392156862745098,'#26828e'], [0.5019607843137255,'#21918c'],
            [0.5647058823529412,'#1fa088'], [0.6274509803921569,'#28ae80'],[0.6901960784313725,'#3fbc73'],
            [0.7529411764705882,'#5ec962'], [0.8156862745098039,'#84d44b'], [0.8784313725490196,'#addc30'],
            [0.9411764705882353,'#d8e219'], [1,'#fde725']]
    };

    /*---------------------------------------------------------------------------------------------------------
     ~~~~INITIALIZE & ANIMATE SYNMAP~~~~
     --------------------------------------------------------------------------------------------------------*/

    initialize();
    animate();

    /*---------------------------------------------------------------------------------------------------------
     ~~~~MINOR FUNCTIONS~~~~
     --------------------------------------------------------------------------------------------------------*/

    /* FUNCTION: Index Chromosome Info by Name */
    function indexChr(chr) {
        var chrIndexed = {};
        chr.forEach( function(e) {
            chrIndexed[e.name] = e;
        });
        return chrIndexed
    }

    /* FUNCTION: Sort Chromosome List */
    function sortChr(a,b){
        first = parseInt(a.name);
        second = parseInt(b.name);

        if (isNaN(first) && isNaN(second)) {
            if (a.name < b.name) {
                return -1;
            } else if (a.name > b.name) {
                return 1;
            }
        } else if (isNaN(first)) {
            return 1;
        } else if (isNaN(second)) {
            return -1;
        } else {

            if(first == second) {
                if (a.name < b.name) {
                    return -1;
                } else if (a.name > b.name) {
                    return 1;
                }
            }

            else if(first < second) {
                return -1;
            }

            else if(first > second) {
                return 1;
            }}
    }

    /* FUNCTION: Build Axis from Chromosome List */
    function buildAxisFromChr(chr, focusAxis) {
        var axis = new THREE.Object3D();
        var colorToggle = true;

        var altAxes = ['x', 'y', 'z'];
        altAxes.splice(altAxes.indexOf(focusAxis), 1);

        var colorOne, colorTwo;
        switch (focusAxis) {
            case "x":
                colorOne = 'darkred';
                colorTwo = 'red';
                break;
            case "y":
                colorOne = 'darkblue';
                colorTwo = 'blue';
                break;
            case "z":
                colorOne = 'green';
                colorTwo = 'lightgreen';
                break;
            default:
                colorOne = '';
                colorTwo = '';
        }

        chr.forEach(function (e) {
            var chLen = e.length * scaleFactor;

            var chGeo;
            if (focusAxis == 'x') {
                chGeo = new THREE.BoxGeometry( chLen, axisWidth, axisWidth );
            } else if (focusAxis == 'y') {
                chGeo = new THREE.BoxGeometry( axisWidth, chLen, axisWidth );
            } else if (focusAxis == 'z') {
                chGeo = new THREE.BoxGeometry( axisWidth, axisWidth, chLen );
            } else {
                console.log("Invalid Focus Axis, please select x y or z");
            }

            var chMat;
            if (colorToggle) {
                chMat = new THREE.MeshBasicMaterial({color: colorOne});
                colorToggle = false;
            } else {
                chMat = new THREE.MeshBasicMaterial({color: colorTwo});
                colorToggle = true;
            }

            var ch = new THREE.Mesh( chGeo, chMat );

            ch.position[focusAxis] = startPositions[focusAxis] + (chLen / 2);
            ch.position[altAxes[0]] = -(axisWidth / 2);
            ch.position[altAxes[1]] = -(axisWidth / 2);

            axis.add( ch );

            e["start"] = startPositions[focusAxis];
            startPositions[focusAxis] += chLen;
            e["end"] = startPositions[focusAxis];
        });

        return axis;
    }

    /* FUNCTION: Create Point Coloring Function */
    function getPtColorFunc(histogramData, colorScheme) {
        var minVal = Math.min.apply(null, histogramData);
        var maxVal = Math.max.apply(null, histogramData);
        var N = colorScheme.length,
            domain = new Array(N),
            range = new Array(N),
            si;

        for (var i = 0; i < N; i++) {
            si = colorScheme[i];
            domain[i] = minVal + si[0] * (maxVal - minVal);
            range[i] = si[1]
        }

        var calcColor = d3.scale.linear()
                .domain(domain)
                .interpolate(d3.interpolateRgb)
                .range(range);

        return calcColor
    }

    /* FUNCTION: Generate Gene Pair Info HTML */
    function displayGenePair(ptdata, gid) {
        return "<p><span style='font-weight:bolder'>Name: </span>" + ptdata[gid].name + " </p> \
                <p><span style='font-weight:bolder'>Chromosome: </span>" + ptdata[gid].chr + "</p> \
                <p><span style='font-weight:bolder'>Strand: </span>" + ptdata[gid].strand + "</p> \
                <p><span style='font-weight:bolder'>Start: </span>" + ptdata[gid].start + "</p> \
                <p><span style='font-weight:bolder'>Stop: </span>" + ptdata[gid].stop + "</p> \
                <p><span style='font-weight:bolder'>Gene Count: </span>" + ptdata[gid].gene_count + "</p> \
                <p><span style='font-weight:bolder'>Percent ID: </span>" + ptdata[gid].percent_id + "</p> \
                <p><span style='font-weight:bolder'>Type: </span>" + ptdata[gid].type + "</p> \
                <p><span style='font-weight:bolder'>DB Feature ID: </span>" + ptdata[gid].db_feature_id + "</p>"
    }

    /* FUNCTION: Generate GEvo Link */
    function genGevoLink(xDbId, yDbId, zDbId) {
        // https://genomevolution.org/wiki/index.php/Linking_to_GEvo
        var linkbase = "http://genomevolution.org/coge/GEvo.pl?";
        var seqX = 'fid1=' + xDbId + ';';
        var seqY = 'fid2=' + yDbId + ';';
        var seqZ = 'fid3=' + zDbId + ';';
        var range = 'apply_all=50000;';
        var numSeq = 'num_seqs=3';
        return linkbase + seqX + seqY + seqZ + range + numSeq;
    }
    /*---------------------------------------------------------------------------------------------------------
     ~~~~MAJOR FUNCTIONS: CREATE 3D OBJECTS~~~~
     --------------------------------------------------------------------------------------------------------*/

    /* FUNCTION: Draw Points */
    function drawPoints() {
        // Generate function to calculate point colors by colorscheme.
        var calcPtColor = getPtColorFunc(histogram_data.logten.data[knKsSelect][comparisonSelect], schemes[colorSelect]);
        // Load point image.
        var loader = new THREE.TextureLoader();
        var sprite = loader.load("picts/ball.png");
        // Define plot geometry & material & color array.
        var plotGeo = new THREE.Geometry();
        //plotGeo.addAttribute(size, new THREE.BufferAttribute( size, 1 ));
        var plotMat = new THREE.PointsMaterial( {size: POINT_SIZE, sizeAttenuation: false, map: sprite,
            vertexColors: THREE.VertexColors, alphaTest: 0.5, transparent: true });
        var colors = [];

        //Set up point counter.
        var ptCount = 0;

        // Build points.
        for (x_ch in matches) {
            for (y_ch in matches[x_ch]) {
                for (z_ch in matches[x_ch][y_ch]) {
                    for (index in matches[x_ch][y_ch][z_ch]) {
                        var coordinate = matches[x_ch][y_ch][z_ch][index];
                        var xPos = coordinate[0];
                        var yPos = coordinate[1];
                        var zPos = coordinate[2];
                        var knks = coordinate[3][comparisonSelect][knKsSelect];
                        var ptdata = coordinate[4];

                        // Assign position.
                        var vertex = new THREE.Vector3();
                        vertex.x = xChrIndexed[x_ch]['start'] + (xPos * scaleFactor);
                        vertex.y = yChrIndexed[y_ch]['start'] + (yPos * scaleFactor);
                        vertex.z = zChrIndexed[z_ch]['start'] + (zPos * scaleFactor);
                        plotGeo.vertices.push(vertex);

                        // Assign color.
                        var logKnKs = knks != 0 ? Math.log10(knks) : 'NA';
                        if (isNaN(logKnKs)) {
                            colors[ptCount] = new THREE.Color("#fff");
                        } else {
                            colors[ptCount] = new THREE.Color(calcPtColor(logKnKs));
                        }

                        // Push point data
                        pointData.push(ptdata);

                        ptCount += 1;
                    }
                }
            }
        }
        // Apply colors to geometry.
        plotGeo.colors = colors;

        // Create points object.
        var pts = new THREE.Points(plotGeo, plotMat);

        // Shift points object to rotation offset.
        pts.translateX(-startPositions.x / 2);
        pts.translateY(-startPositions.y / 2);
        pts.translateZ(-startPositions.z / 2);

        // Add points object to scene.
        //scene.add(points);

        // Report point count.
        console.log("POINTS RENDERED: " + ptCount);
        return pts;
    }

    /* FUNCTION: Draw Chromosomes */
    function drawChromosomes() {
        /* Sort and Index Chromosomes */
        xChr.sort(sortChr);
        yChr.sort(sortChr);
        zChr.sort(sortChr);
        xChrIndexed = indexChr(xChr);
        yChrIndexed = indexChr(yChr);
        zChrIndexed = indexChr(zChr);

        /* 3d Object: Axes */
        xAxis = buildAxisFromChr(xChr, 'x');
        yAxis = buildAxisFromChr(yChr, 'y');
        zAxis = buildAxisFromChr(zChr, 'z');

        xAxis.translateX(-startPositions.x / 2);
        xAxis.translateY(-startPositions.y / 2);
        xAxis.translateZ(-startPositions.z / 2);

        yAxis.translateX(-startPositions.x / 2);
        yAxis.translateY(-startPositions.y / 2);
        yAxis.translateZ(-startPositions.z / 2);

        zAxis.translateX(-startPositions.x / 2);
        zAxis.translateY(-startPositions.y / 2);
        zAxis.translateZ(-startPositions.z / 2);

        //scene.add(xAxis);
        //scene.add(yAxis);
        //scene.add(zAxis);
        return [xAxis, yAxis, zAxis];
    }

    /* FUNCTION: Draw Grid */
    function drawGrid() {
        var g = new THREE.Object3D();
        var gridWidth = 0.025;
        var gridMat = new THREE.MeshBasicMaterial({color: 'grey'});

        yChr.forEach( function(e) {
            var yxGridGeo = new THREE.BoxGeometry( startPositions.x, gridWidth, gridWidth );
            var yxGrid = new THREE.Mesh( yxGridGeo, gridMat );
            yxGrid.position.x = (startPositions.x / 2);
            yxGrid.position.y = e.end;
            yxGrid.position.z = 0;
            g.add(yxGrid);

            var yzGridGeo = new THREE.BoxGeometry (gridWidth, gridWidth, startPositions.z);
            var yzGrid = new THREE.Mesh( yzGridGeo, gridMat);
            yzGrid.position.x = 0;
            yzGrid.position.y = e.end; //(yStartPos / 2);
            yzGrid.position.z = (startPositions.z / 2);
            g.add(yzGrid)
        });

        xChr.forEach( function(e) {
            var hGridGeo = new THREE.BoxGeometry( gridWidth, gridWidth, startPositions.z );
            var hGrid = new THREE.Mesh( hGridGeo, gridMat );
            hGrid.position.x = e.end;
            hGrid.position.y = 0;
            hGrid.position.z = (startPositions.z / 2);
            g.add(hGrid);

            var vGridGeo = new THREE.BoxGeometry (gridWidth, startPositions.y, gridWidth);
            var vGrid = new THREE.Mesh( vGridGeo, gridMat);
            vGrid.position.x = e.end;
            vGrid.position.y = (startPositions.y /2);
            vGrid.position.z = 0;
            g.add(vGrid)
        });

        zChr.forEach( function(e) {
            var hGridGeo = new THREE.BoxGeometry( startPositions.x, gridWidth, gridWidth );
            var hGrid = new THREE.Mesh( hGridGeo, gridMat );
            hGrid.position.x = (startPositions.x / 2);
            hGrid.position.y = 0;
            hGrid.position.z = e.end;
            g.add(hGrid);

            var vGridGeo = new THREE.BoxGeometry (gridWidth, startPositions.y, gridWidth);
            var vGrid = new THREE.Mesh( vGridGeo, gridMat);
            vGrid.position.x = 0;
            vGrid.position.y = (startPositions.y / 2);
            vGrid.position.z = e.end;
            g.add(vGrid)
        });

        g.translateX(-startPositions.x / 2);
        g.translateY(-startPositions.y / 2);
        g.translateZ(-startPositions.z / 2);
        //scene.add(grid);
        return g;
    }

    /*---------------------------------------------------------------------------------------------------------
     ~~~~INITIALIZE~~~~
     --------------------------------------------------------------------------------------------------------*/

    function initialize() {
        //width = window.innerWidth * 0.689;
        //height = window.innerHeight * 0.9;
        width = document.getElementById("rendering").clientWidth;
        height = window.innerHeight * 0.9;
        containerWidth = container.clientWidth;
        containerHeight = container.clientHeight;

        /* Create a three.js scene */
        scene = new THREE.Scene();

        /* Setup three.js WebGL renderer */
        renderer = new THREE.WebGLRenderer( { antialias: true, alpha: true, canvas: container} );
        renderer.setSize( width, height );

        /* Create a three.js camera */
        camera = new THREE.PerspectiveCamera( 75, width / height, 1, 1000 );
        camera.position.x = camView.x;
        camera.position.y = camView.y;
        camera.position.z = camView.z;

        /* Apply FlatOrbitControls to camera. */
        controls = new THREE.FlatOrbitControls( camera );

        /* Add raycaster */
        raycaster = new THREE.Raycaster();
        mouse = new THREE.Vector2();

        // Clear point data.
        //pointData = [];

        /* Create chromosome axes */
        var axes = drawChromosomes();
        for (var i = 0; i < axes.length; i++) {
            scene.add(axes[i])
        }

        /* Create grid */
        grid = drawGrid();
        scene.add(grid);

        /* Create points geometry */
        points = drawPoints();
        scene.add(points);

    }

    /*---------------------------------------------------------------------------------------------------------
     ~~~~RENDER~~~~
     --------------------------------------------------------------------------------------------------------*/

    function render() {
        // Render scene.
        renderer.render( scene, camera );
    }

    /*---------------------------------------------------------------------------------------------------------
     ~~~~ANIMATE~~~~
     --------------------------------------------------------------------------------------------------------*/

    function animate() {
        /* Update controls. */
        controls.update();

        /* Update camera position record. */
        camView = { "x": camera.position.x, "y": camera.position.y, "z": camera.position.z };

        /* Render the scene. */
        render();

        /* Create continuous animation. */
        requestAnimationFrame( animate );
    }

    /*---------------------------------------------------------------------------------------------------------
     ~~~~HANDLERS~~~~
     --------------------------------------------------------------------------------------------------------*/

    /* Window Resize */
    function onWindowResize() {
        width = document.getElementById("rendering").clientWidth;
        height = window.innerHeight * 0.9;
        renderer.setSize( width, height);
        camera.aspect = width / height;
        camera.updateProjectionMatrix();

        containerWidth = container.clientWidth;
        containerHeight = container.clientHeight;

        renderHistogram(document.getElementById("histogram"), comparisonSelect + " log(" + knKsSelect + ")",
            histogram_data.logten.data[knKsSelect][comparisonSelect], 100);
    }
    window.addEventListener( 'resize', onWindowResize, false );

    /* Mouse Click */
    function onDocumentMouseDown( event ) {
        // Specify object of interest (points).
        var geometry = points.geometry;

        // Calculate mouse location on canvas.
        var offset_l = $("canvas").offset().left - $(window).scrollLeft();
        var offset_t = $("canvas").offset().top - $(window).scrollTop();
        mouse.x = ( (event.clientX - offset_l) / container.clientWidth ) * 2 - 1;
        mouse.y = -( (event.clientY - offset_t) / container.clientHeight ) * 2 + 1;

        // Cast ray & find intersects.
        raycaster.setFromCamera( mouse, camera );
        intersects = raycaster.intersectObject( points );

        // Actions when intersects are found.
        if (intersects.length > 0) {
            // Set INTERSECTED to closest intersected point.
            INTERSECTED = intersects[ 0 ].index;
            // Assign INTERSECTED point data to pt_select.
            var pt_select = pointData[ INTERSECTED ];
            // Show point info panels & GEvo button.
            $(".gene-info-display").css("display", "");
            $("#gevo_div").css("display", "");
            // Select info panels.
            var xdisplay = $("#x-gene-display");
            var ydisplay = $("#y-gene-display");
            var zdisplay = $("#z-gene-display");
            // Empty old content from info panels.
            xdisplay.empty();
            ydisplay.empty();
            zdisplay.empty();
            // Print intersected point data to respective info panels.
            xdisplay.append(displayGenePair(pt_select, final_experiment.x_gid));
            ydisplay.append(displayGenePair(pt_select, final_experiment.y_gid));
            zdisplay.append(displayGenePair(pt_select, final_experiment.z_gid));

            // Build GEvo link.
            var gevoLink = genGevoLink(
                pt_select[final_experiment.x_gid].db_feature_id,
                pt_select[final_experiment.y_gid].db_feature_id,
                pt_select[final_experiment.z_gid].db_feature_id);
            // Assign link to click event.
            document.getElementById("gevo_button").onclick = function() { window.open(gevoLink) };

            // Revert previously selected point color.
            if (ptHistory[0] != "NULL") { geometry.colors[ ptHistory[0] ] = ptHistory[1]; }
            // Record new point index & color.
            ptHistory = [INTERSECTED, geometry.colors[INTERSECTED]];
            // Change intersected point color to black.
            geometry.colors[ INTERSECTED ] = black;
            // Trigger color update.
            geometry.colorsNeedUpdate = true;

        } else if ( INTERSECTED !== null ) {
            // Clear INTERSECTED variable if no intersections on click.
            INTERSECTED = null;
        }
    }
    window.addEventListener('mousedown', onDocumentMouseDown, false);

    /* Grid Toggle */
    var grid_state = 1;
    function onGridToggle() {
        if (grid_state == 1) {
            grid_state = 0;
            scene.remove(grid);
        } else {
            grid_state = 1;
            scene.add(grid);
        }
    }
    var GridToggle = document.getElementById("grid_toggle");
    GridToggle.addEventListener("click", onGridToggle)

} //END renderSynMap()

/*-----------------------------------------------------------------------------------------------------------------
 ~~~~ POPULATE PAGE ~~~~
 -----------------------------------------------------------------------------------------------------------------*/
// TODO: Add spinny waiting queue
// TODO: IS RE-LOADING AFTER NEW OPTIONS SELECTED CLEARING THE OBJECTS AND REDOING THEM OR JUST WRITING OVER!?!?!

// On Document Ready
$(document).ready( function() {
    var load;

    /* Monitor Color Scheme */
    var ColorSelector = $("#color_select");
    colorSelect = ColorSelector.val();
    ColorSelector.change( function () {
        colorSelect = ColorSelector.val();
        renderSynMap(load.xChr, load.yChr, load.zChr, load.matches, load.histogram_data);
        renderHistogram(document.getElementById("histogram"), comparisonSelect + " log(" + knKsSelect + ")",
            load.histogram_data.logten.data[knKsSelect][comparisonSelect], 100);
    });

    /* Monitor KnKsSelect */
    var KnKsSelector = $("#knks_select");
    knKsSelect = KnKsSelector.val();
    KnKsSelector.change( function() {
        knKsSelect = KnKsSelector.val();
        renderSynMap(load.xChr, load.yChr, load.zChr, load.matches, load.histogram_data);
        renderHistogram(document.getElementById("histogram"), comparisonSelect + " log(" + knKsSelect + ")",
            load.histogram_data.logten.data[knKsSelect][comparisonSelect], 100);
    });

    /* Monitor Comparison Select */
    var ComparisonSelector = $("#comparison_select");
    comparisonSelect = ComparisonSelector.val();
    ComparisonSelector.change( function() {
        comparisonSelect = ComparisonSelector.val();
        renderSynMap(load.xChr, load.yChr, load.zChr, load.matches, load.histogram_data);
        renderHistogram(document.getElementById("histogram"), comparisonSelect + " log(" + knKsSelect + ")",
            load.histogram_data.logten.data[knKsSelect][comparisonSelect], 100);
    });

    var visOpts = [ColorSelector, KnKsSelector, ComparisonSelector];

    /* Load Data & Render Visualization on Page Load */
    $.when(loadData(
        final_experiment.x_gid, final_experiment.y_gid, final_experiment.z_gid,
        final_experiment.links.xy_json, final_experiment.links.xz_json,
        final_experiment.links.merge,
        final_experiment.links.histo))
    .done(function(data) {
        // Save data into upper scope
        load = data;
        // Render SynMap
        renderSynMap(data.xChr, data.yChr, data.zChr, data.matches, data.histogram_data);
        //Render Histogram
        renderHistogram(document.getElementById("histogram"), comparisonSelect + " log(" + knKsSelect + ")",
            data.histogram_data.logten.data[knKsSelect][comparisonSelect], 100);
        // Enable Visualization Options
        for (var i= 0; i < visOpts.length; i++) { visOpts[i].prop('disabled', false) }
    }); //END $.when(loadData())

}); //END $(document).ready()
