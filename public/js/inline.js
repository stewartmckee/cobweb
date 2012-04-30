$(document).ready(function() {

    // MENU
    $(".menu-search ul li li:first-child a").css("border-top", "none");
    $(".menu-search ul").supersubs({
        minWidth: 15,
        maxWidth: 40
    }).superfish({
        autoArrows: false,
        dropShadows: false
    });

    var htmlStr = $("code").html();
    $("code").text(htmlStr);

    // BOX HIDE
    $('span.hide').click(function() {
        $(this).parent().next('.content').fadeToggle(100);
    });

    // TITLE SEARCH BOX
    $('.box-search').hide();
    $('span.search').click(function() {
        $('.box-search').fadeTo(800, 1.0).end();
        $('span.search').hide();
    });

    // THUMB OPTIONS
    $("a.zoom").fancybox({
        'speedIn': 600,
        'speedOut': 200,
        'overlayShow': true,
        'overlayColor': '#000',
        'titlePosition': 'over'
    });
    $("img.shadow").wrap("<span class='shadow'></span>");
    $("img.left").wrap("<span class='shadow left'></span>");
    $("img.right").wrap("<span class='shadow right'></span>");
    $(function() {
        $("div.thumb").hover(
        function() {
            $(this).children("img").fadeTo(200, 0.85).end().children("div").show();
        }, function() {
            $(this).children("img").fadeTo(200, 1).end().children("div").hide();
        });
    });

    // SYSTEM MESSAGES
    $(".messages:first-child").css({
        "margin": "0 0 1px"
    });

    // MESSAGE BOX
    $(".content .message:last-child").css({
        "border-bottom": "none",
        "padding": "12px 0 0"
    });

    if ($.browser.msie && $.browser.version.substr(0, 1) < 8) {
        $(".content .message:last-child").css({
            "border-bottom": "none",
            "padding": "11px 0 0"
        });
    }

    // MODAL BOXES
    $(function() {
        $(".modal").dialog({
            autoOpen: false,
            closeText: '',
            resizable: false,
            width: 700,
			height: 500
        });

        $('.modalopen').click(function() {
            $(".modal").dialog('open');
            return false;
        });
    });

    // TABS, ACCORDIONS, TREEVIEW & TOOLTIPS
    $(".tabs").tabs({
        fx: {
            opacity: 'toggle'
        }
    });

    $(".accordion").accordion({
        autoHeight: false,
        navigation: true
    });

    $(".filetree").treeview({
        persist: "location",
        collapsed: true
    });

    $(".tooltip").tipsy();

    // DATATABLE
    $('table.all').dataTable({
        "bInfo": false,
        "iDisplayLength": 5,
        "aLengthMenu": [[5, 10, 25, 50, 100], [5, 10, 25, 50, 100]],
        "sPaginationType": "full_numbers",
        "bPaginate": true,
        "aoColumnDefs": [{
            bSortable: false,
            aTargets: [0]}],
        "sDom": 't<plf>'
    });

    $('table.sortsearch').dataTable({
        "bInfo": false,
        "bPaginate": false,
        "aoColumnDefs": [{
            bSortable: false,
            aTargets: [0]}],
        "sDom": 't<plf>'
    });

    $('table.sorting').dataTable({
        "bInfo": false,
        "bPaginate": false,
        "bFilter": false,
        "aoColumnDefs": [{
            bSortable: false,
            aTargets: [0]}],
        "sDom": 't<plf>'
    });

    $(".dataTables_wrapper .dataTables_length select").addClass("entries");

    $(function() {
        $(".dataTables_paginate span.paginate_button").hover(
        function() {
            $(this).fadeTo(200, 0.85).end();
        }, function() {
            $(this).fadeTo(200, 1).end();
        });
    });

    // CHECK ALL PAGES
    $('.checkall').click(function() {
        $(this).parents('table').find(':checkbox').attr('checked', this.checked);
    });

    // BUTTON LINKS
    $("a.button").wrapInner("<span></span>");
    $("a.button, button, .pager img").hover(

    function() {
        $(this).stop().fadeTo(200, 0.7);
    }, function() {
        $(this).stop().fadeTo(200, 1.0);
    });

    // STYLE FILE BUTTON
    $("input[type=file]").wrap("<div style='display : inline-block; overflow : hidden; width : auto; height : 27px;'></div>");
    $("input[type=file]").filestyle({
        imageheight: 27,
        imagewidth: 65,
        width: 166
    });

    // SLIDER
    $(".range-slide div.slide").each(function() {
        values = $(this).attr('value').split(',');
        firstVal = values[0];
        secondVal = values[1];

        rangeInputfirst = $(this).siblings('input.amount-first');
        rangeInputsecond = $(this).siblings('input.amount-second');

        $(this).slider({
            values: [firstVal, secondVal],
            min: parseInt($(this).attr('min'), 0),
            max: parseInt($(this).attr('max'), 0),
            range: true,
            slide: function(event, ui) {
                $(this).siblings('input.amount-first').val("" + ui.values[0]);
                $(this).siblings('input.amount-second').val("" + ui.values[1]);
            }
        });
        rangeInputfirst.val("" + $(this).slider("values", 0));
        rangeInputsecond.val("" + $(this).slider("values", 1));
    });

    $(".signle-slide div.slide").each(function() {
        value = $(this).attr('value').split(',');
        firstVal = value;

        rangeSpan = $(this).siblings('input.amount');

        $(this).slider({
            value: [firstVal],
            min: parseInt($(this).attr('min'), 0),
            max: parseInt($(this).attr('max'), 0),
            slide: function(event, ui) {
                $(this).siblings('input.amount').val("" + ui.value);
            }
        });
        rangeSpan.val("" + $(this).slider("value"));
    });

    // PROGRESSBAR
    $(".progressbar div").progressbar({
        value: 100
    });

    // AUTOCOMPLETE
    $(function() {
        var availableTags = [
            "ActionScript",
            "AppleScript",
            "Asp",
            "BASIC",
            "C",
            "C++",
            "Clojure",
            "COBOL",
            "ColdFusion",
            "Erlang",
            "Fortran",
            "Groovy",
            "Haskell",
            "Java",
            "JavaScript",
            "Lisp",
            "Perl",
            "PHP",
            "Python",
            "Ruby",
            "Scala",
            "Scheme"
            ];
        $(".complete").autocomplete({
            source: availableTags
        });
    });

    // FORMS
    $(".line:odd").css({
        "border-top": "2px solid #f2f4f7",
        "border-bottom": "2px solid #f2f4f7"
    });
    $(".line:first-child").css({
        "border-top": "none"
    });
    $(".line:last-child").css({
        "border-bottom": "none"
    });
	
	$("input.datepicker").datepicker({
		dateFormat: 'mm.dd.yy'
	});
	
	$("input.timepicker").datetimepicker({});

    $(function() {
        $('.dataTables_length input, select').not("select.multi").selectmenu({
            style: 'dropdown',
            transferClasses: true,
            width: null
        });
    });

    $("input[type=radio], input[type=checkbox]").each(function() {
        if ($(this).parents("table").length === 0) {
            $(this).customInput();
        }
    });

    $('.hide-input input, .filter-box, .search input, .box-search input').click(function() {
        if (this.value === this.defaultValue) {
            this.value = '';
        }
    });

    $('.hide-input input, .filter-box, .search input, .box-search input').blur(function() {
        if (this.value === '') {
            this.value = this.defaultValue;
        }
    });

    // Input and textarea IE 7 fix
    if ($.browser.msie && $.browser.version.substr(0, 1) < 8) {
        $("input.tiny").wrap("<div class='input-tiny'></div>");
        $("input.small").wrap("<div class='input-small'></div>");
        $("input.medium").wrap("<div class='input-medium'></div>");
        $("input.big").wrap("<div class='input-big'></div>");
        $("input.xl").wrap("<div class='input-xl'></div>");
        $("textarea.small").wrap("<div class='textarea-small'></div>");
        $("textarea.medium").wrap("<div class='textarea-medium'></div>");
        $("textarea.big").wrap("<div class='textarea-big'></div>");
        $("textarea.xl").wrap("<div class='textarea-xl'></div>");
    }

    // WYSISWYG
    $('.wysiwyg').wysiwyg({
        css: "css/wysiwyg-editor.css",
        plugins: {
            rmFormat: {
                rmMsWordMarkup: true
            }
        }
    });

    // TABEL STATICS        
    $("table.statics").each(function() {
        var colors = [];
        $("table.statics thead th:not(:first)").each(function() {
            colors.push($(this).css("color"));
        });
        $(this).graphTable({
            series: 'columns',
            position: 'replace',
			width : '100%',
            height: '200px',
            colors: colors
        }, {
            xaxis: {
                tickSize: 1
            }
        });
    });

    $("table.statics-date").each(function() {
        var colors = [];
        var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

        $("table.statics-date thead th:not(:first)").each(function() {
            colors.push($(this).css("color"));
        });
        $(this).graphTable({
            series: 'columns',
            position: 'replace',
			width : '100%',
            height: '200px',
            colors: colors,
            xaxisTransform: function(month) {
                var i = 0;
                while ((i < 12) && (month != months[i])) {
                    i++;
                }
                return i;
            }
        }, {
            xaxis: {
                tickSize: 1,
                tickFormatter: function(v, a) {
                    return months[v];
                }
            }
        });
    });

    $('.flot-graph').before('<div class="space"></div>');

    function showTooltip(x, y, contents) {
        $('<div id="tooltip">' + contents + '</div>').css({
            position: 'absolute',
            display: 'none',
            top: y + 5,
            left: x + 5
        }).appendTo("body").fadeIn("fast");
    }

    var previousPoint = null;
    $(".flot-graph").bind("plothover", function(event, pos, item) {
        $("#x").text(pos.x);
        $("#y").text(pos.y);

        if (item) {
            if (previousPoint != item.dataIndex) {
                previousPoint = item.dataIndex;

                $("#tooltip").remove();
                var x = item.datapoint[0],
                    y = item.datapoint[1];

                showTooltip(item.pageX, item.pageY, "<b>" + item.series.label + "</b>: " + y);
            }
        }
        else {
            $("#tooltip").remove();
            previousPoint = null;
        }
    });

});