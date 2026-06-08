(function ($) {

  "use strict";

  $(window).on('load', function () {
    // 1) Fade out preloader
    $('#preloader').fadeOut();

    // 2) Sticky Nav + immediate trigger
    $(window).on('scroll', function () {
      const scroll = $(window).scrollTop();
      if (scroll > 200) {
        $('.scrolling-navbar').addClass('top-nav-collapse');
      } else {
        $('.scrolling-navbar').removeClass('top-nav-collapse');
      }

      // Add class when scrolled past the announcement banner
      if (scroll > 40) {
        $('.scrolling-navbar').addClass('past-banner');
      } else {
        $('.scrolling-navbar').removeClass('past-banner');
      }
    });
    $(window).trigger('scroll');

    // 3) Auto‐close on mobile (only non‐dropdown links)
    function close_toggle() {
      if ($(window).width() <= 768) {
        $('.navbar-collapse a:not(.dropdown-toggle)').on('click', function () {
          $('.navbar-collapse').collapse('hide');
        });
      } else {
        $('.navbar-collapse a').off('click');
      }
    }
    close_toggle();
    $(window).resize(close_toggle);

    // —— TRAVEL DROPDOWN ACTIVE & AUTO‐COLLAPSE ——
    (function () {
      const $travelToggle = $('#travelDropdown');
      const page = window.location.pathname.split('/').pop().toLowerCase();
      if (page === 'travel.html') {
        $travelToggle.addClass('active');
      } else {
        $travelToggle.removeClass('active');
      }
      $('.dropdown-menu .dropdown-item').on('click', function () {
        $travelToggle.addClass('active');
        $('.navbar-collapse').collapse('hide');
      });
    })();

    /* ==========================================================================
       countdown timer
       ========================================================================== */
    jQuery('#clock').countdown('2026/7/9', function (event) {
      var $this = jQuery(this).html(event.strftime(''
        + '<div class="time-entry days"><span>%-D</span> <b>:</b> Days</div> '
        + '<div class="time-entry hours"><span>%H</span> <b>:</b> Hours</div> '
        + '<div class="time-entry minutes"><span>%M</span> <b>:</b> Minutes</div> '
        + '<div class="time-entry seconds"><span>%S</span> Seconds</div> '));
    });




    /* Auto Close Responsive Navbar on Click
    ========================================================*/
    /* Auto‐close on mobile only when a non‐dropdown link is clicked */
    function close_toggle() {
      if ($(window).width() <= 768) {
        // bind only links that are NOT the top‐level dropdown toggles
        $('.navbar-collapse a:not(.dropdown-toggle)').on('click', function () {
          $('.navbar-collapse').collapse('hide');
        });
      } else {
        // unbind when on desktop
        $('.navbar-collapse a').off('click');
      }
    }

    // run once on load
    close_toggle();
    // re‐apply on every resize
    $(window).resize(close_toggle);


    /* WOW Scroll Spy
  ========================================================*/
    var wow = new WOW({
      //disabled for mobile
      mobile: false
    });
    wow.init();

    /* Nivo Lightbox 
    ========================================================*/
    $('.lightbox').nivoLightbox({
      effect: 'fadeScale',
      keyboardNav: true,
    });

    // one page navigation 
    $('.navbar-nav').onePageNav({
      currentClass: 'active'
    });

    /* Counter
    ========================================================*/
    $('.counterUp').counterUp({
      delay: 10,
      time: 1500
    });

    /* Back Top Link active
    ========================================================*/
    var offset = 200;
    var duration = 500;
    $(window).scroll(function () {
      if ($(this).scrollTop() > offset) {
        $('.back-to-top').fadeIn(400);
      } else {
        $('.back-to-top').fadeOut(400);
      }
    });

    $('.back-to-top').on('click', function (event) {
      event.preventDefault();
      $('html, body').animate({
        scrollTop: 0
      }, 600);
      return false;
    });

    // —— REGISTRATION BANNER LOGIC ——
    (function () {
      // Define dismissal function globally
      window.dismissBanner = function () {
        const banner = document.getElementById('registration-banner');
        if (banner) {
          banner.style.display = 'none';
          document.body.classList.remove('has-banner');
          localStorage.setItem('registrationExtensionBannerDismissed', 'true');
        }
      };

      const isRegistrationPage = window.location.pathname.toLowerCase().includes('registration.html');
      if (isRegistrationPage) return;

      const now = new Date();
      const deadline = new Date('2026-06-15T23:59:59+03:00');
      const isDismissed = localStorage.getItem('registrationExtensionBannerDismissed');

      if (now <= deadline && !isDismissed) {
        const bannerHtml = `
          <div id="registration-banner" class="announcement-banner">
            <div class="container">
              <div class="banner-content">
                <span class="banner-text">
                  <i class="lni-star-filled mr-1" style="color: #ffca28;"></i>
                  <strong>Early-bird registration extended!</strong> Early-bird pricing is now valid until June 15, 2026.
                </span>
                <a href="registration.html" class="btn-banner">Register Now</a>
                <button class="banner-close" onclick="dismissBanner()" title="Dismiss">
                  <i class="lni-close"></i>
                </button>
              </div>
            </div>
          </div>`;
        
        // Inject at the very beginning of body
        document.body.insertAdjacentHTML('afterbegin', bannerHtml);
        document.body.classList.add('has-banner');
      }
    })();

  });

}(jQuery));
